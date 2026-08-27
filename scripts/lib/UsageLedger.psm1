Set-StrictMode -Version Latest

$usageContractPath = Join-Path $PSScriptRoot 'UsageContract.psm1'
$governanceCommonPath = Join-Path $PSScriptRoot 'GovernanceCommon.psm1'
Import-Module $usageContractPath -ErrorAction Stop
Import-Module $governanceCommonPath -ErrorAction Stop

$script:maximumLedgerBytes = 64MB
$script:lockTimeout = [TimeSpan]::FromSeconds(10)
$script:utf8 = [Text.UTF8Encoding]::new($false, $true)

function Get-UsageLedgerSchemaPath {
    param([Parameter(Mandatory)][string]$FileName)

    $path = [IO.Path]::GetFullPath((
        Join-Path $PSScriptRoot "..\..\evals\schemas\$FileName"
    ))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Canonical usage schema is missing: $FileName"
    }
    return $path
}

function Assert-UsageLedgerSchemaValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaFileName,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        $json = $Value | ConvertTo-Json -Depth 32
        $valid = Test-Json `
            -Json $json `
            -SchemaFile (Get-UsageLedgerSchemaPath -FileName $SchemaFileName) `
            -ErrorAction Stop
        if (-not $valid) { throw 'JSON Schema validation returned false.' }
    } catch {
        throw "$Label does not conform to its canonical schema."
    }
}

function Get-UsageLedgerSha256 {
    param([Parameter(Mandatory)][string]$Text)

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function ConvertTo-UsageLedgerUtcTimestamp {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Value -is [DateTimeOffset]) {
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTime]) {
        return ([DateTimeOffset]$Value).ToUniversalTime()
    }
    $text = [string]$Value
    if ($text -cnotmatch '(?:Z|[+-]\d{2}:\d{2})$') {
        throw "$Label must include an explicit UTC offset or Z suffix."
    }
    try {
        return [DateTimeOffset]::Parse(
            $text,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
    } catch {
        throw "$Label must be an ISO 8601 timestamp."
    }
}

function ConvertTo-ProjectDCodexUsageEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Projection,
        [Parameter(Mandatory)]$Identity
    )

    Assert-UsageLedgerSchemaValue `
        -Value $Projection `
        -SchemaFileName 'codex-usage-projection.schema.json' `
        -Label 'Codex usage projection'
    if (@(Find-SensitiveValue $Projection).Count -gt 0) {
        throw 'Codex usage projection contains sensitive-looking metadata.'
    }
    if (
        [string]$Identity.provider -cne 'codex' -or
        [string]$Identity.verification_status -cne 'verified'
    ) {
        throw 'Codex usage ingestion requires a verified Codex identity.'
    }

    $identityMaterial = @(
        'codex',
        [string]$Projection.thread_id,
        [string]$Projection.turn_id
    ) | ConvertTo-Json -Compress
    $digest = Get-UsageLedgerSha256 -Text $identityMaterial
    $metrics = [ordered]@{
        input_tokens = $Projection.usage.input_tokens
        cached_input_tokens = $Projection.usage.cached_input_tokens
        output_tokens = $Projection.usage.output_tokens
        reasoning_tokens = $Projection.usage.reasoning_tokens
    }
    if (
        $Projection.usage.PSObject.Properties.Name -ccontains
            'cache_creation_tokens'
    ) {
        $metrics.cache_creation_tokens = (
            $Projection.usage.cache_creation_tokens
        )
    }

    $occurred = ConvertTo-UsageLedgerUtcTimestamp `
        -Value $Projection.occurred_at -Label 'OccurredAt'
    return New-ProjectDUsageEvent `
        -EventId "evt_codex_$digest" `
        -SourceEventId "codex_turn_$digest" `
        -SessionId ([string]$Projection.thread_id) `
        -TurnId ([string]$Projection.turn_id) `
        -OccurredAt $occurred.ToString('o') `
        -Identity $Identity `
        -Model ([string]$Projection.model) `
        -Metrics $metrics
}

function ConvertTo-ProjectDCodexQuotaSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Projection,
        [Parameter(Mandatory)]$Identity
    )

    Assert-UsageLedgerSchemaValue `
        -Value $Projection `
        -SchemaFileName 'codex-quota-projection.schema.json' `
        -Label 'Codex quota projection'
    if (@(Find-SensitiveValue $Projection).Count -gt 0) {
        throw 'Codex quota projection contains sensitive-looking metadata.'
    }
    if (
        [string]$Identity.provider -cne 'codex' -or
        [string]$Identity.verification_status -cne 'verified'
    ) {
        throw 'Codex quota ingestion requires a verified Codex identity.'
    }
    $captured = ConvertTo-UsageLedgerUtcTimestamp `
        -Value $Projection.captured_at `
        -Label 'CapturedAt'
    $keys = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $windows = @(
        foreach ($window in @($Projection.windows)) {
            $key = "$([string]$window.limit_id):$([string]$window.window)"
            if (-not $keys.Add($key)) {
                throw 'Codex quota projection contains a duplicate window.'
            }
            [pscustomobject][ordered]@{
                limit_id = [string]$window.limit_id
                window = [string]$window.window
                used_percent = [int]$window.used_percent
                window_duration_minutes = if (
                    $null -eq $window.window_duration_minutes
                ) { $null } else { [long]$window.window_duration_minutes }
                resets_at = if ($null -eq $window.resets_at) {
                    $null
                } else { [long]$window.resets_at }
            }
        }
    )
    $snapshot = [pscustomobject][ordered]@{
        schema_version = 1
        captured_at = $captured.ToString('o')
        provider = 'codex'
        identity = [pscustomobject][ordered]@{
            verification_status = 'verified'
            account_id = [string]$Identity.account_id
            account_alias = [string]$Identity.account_alias
            device_id = [string]$Identity.device_id
            environment = [string]$Identity.environment
            billing_source = [string]$Identity.billing_source
        }
        windows = $windows
    }
    Assert-UsageLedgerSchemaValue `
        -Value $snapshot `
        -SchemaFileName 'codex-quota-snapshot.schema.json' `
        -Label 'Codex quota snapshot'
    return $snapshot
}

function Resolve-ProjectDUsageLedgerPath {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$LedgerPath
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'ProjectRoot must be an existing directory.'
    }
    $usageRoot = [IO.Path]::GetFullPath((
        Join-Path $root '.local\usage'
    )).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $candidate = if ([IO.Path]::IsPathRooted($LedgerPath)) {
        [IO.Path]::GetFullPath($LedgerPath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $LedgerPath))
    }
    $usagePrefix = $usageRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith(
        $usagePrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Usage ledger must stay inside ProjectRoot/.local/usage.'
    }
    if ([IO.Path]::GetExtension($candidate) -cne '.jsonl') {
        throw 'Usage ledger must use the .jsonl extension.'
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $candidate) {
        throw 'Usage ledger path must not cross a reparse point.'
    }
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $candidate
    ) -Force | Out-Null
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $candidate) {
        throw 'Usage ledger path must not cross a reparse point.'
    }
    return $candidate
}

function Resolve-ProjectDUsageQuotaPath {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$SnapshotPath
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'ProjectRoot must be an existing directory.'
    }
    $usageRoot = [IO.Path]::GetFullPath((
        Join-Path $root '.local\usage'
    )).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $candidate = if ([IO.Path]::IsPathRooted($SnapshotPath)) {
        [IO.Path]::GetFullPath($SnapshotPath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $SnapshotPath))
    }
    $usagePrefix = $usageRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith(
        $usagePrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Quota snapshot must stay inside ProjectRoot/.local/usage.'
    }
    if ([IO.Path]::GetExtension($candidate) -cne '.json') {
        throw 'Quota snapshot must use the .json extension.'
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $candidate) {
        throw 'Quota snapshot path must not cross a reparse point.'
    }
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $candidate
    ) -Force | Out-Null
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $candidate) {
        throw 'Quota snapshot path must not cross a reparse point.'
    }
    return $candidate
}

function Enter-ProjectDUsageLedgerLock {
    param([Parameter(Mandatory)][string]$Path)

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            return [IO.FileStream]::new(
                $Path,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None,
                1,
                [IO.FileOptions]::WriteThrough
            )
        } catch [IO.IOException] {
            if ($stopwatch.Elapsed -ge $script:lockTimeout) {
                throw 'Timed out waiting for the usage-ledger writer.'
            }
            Start-Sleep -Milliseconds 50
        }
    } while ($true)
}

function Read-ProjectDUsageLedgerEvents {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt $script:maximumLedgerBytes) {
        throw 'Existing usage ledger exceeds its size limit.'
    }
    if ($item.Length -eq 0) { return @() }
    try {
        $text = $script:utf8.GetString([IO.File]::ReadAllBytes($Path))
    } catch {
        throw 'Existing usage ledger is not valid UTF-8.'
    }

    $records = [Collections.Generic.List[object]]::new()
    $eventIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $sourceIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($line in @((($text -replace "`r", '') -split "`n"))) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw 'Existing usage ledger contains an empty record.'
        }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw 'Existing usage ledger contains invalid JSON.'
        }
        Assert-UsageLedgerSchemaValue `
            -Value $event `
            -SchemaFileName 'usage-events.schema.json' `
            -Label 'Existing usage ledger event'
        if ([string]$event.identity.verification_status -cne 'verified') {
            throw 'Existing usage ledger contains an unverified identity.'
        }
        if (
            -not $eventIds.Add([string]$event.event_id) -or
            -not $sourceIds.Add([string]$event.source_event_id)
        ) {
            throw 'Existing usage ledger contains a duplicate event identity.'
        }
        $records.Add([pscustomobject]@{
            event = $event
            canonical_json = $line
        })
    }
    return @($records)
}

function Write-ProjectDUsageLedgerEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Event,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$LedgerPath
    )

    Assert-UsageLedgerSchemaValue `
        -Value $Event `
        -SchemaFileName 'usage-events.schema.json' `
        -Label 'Usage ledger event'
    if ([string]$Event.identity.verification_status -cne 'verified') {
        throw 'Usage ledger events require a verified account identity.'
    }
    $resolvedPath = Resolve-ProjectDUsageLedgerPath `
        -ProjectRoot $ProjectRoot `
        -LedgerPath $LedgerPath
    $lockPath = "$resolvedPath.lock"
    $resolvedRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if (Test-PathHasReparsePoint -Root $resolvedRoot -ResolvedPath $lockPath) {
        throw 'Usage ledger lock path must not cross a reparse point.'
    }
    $lock = Enter-ProjectDUsageLedgerLock -Path $lockPath
    try {
        $records = @(Read-ProjectDUsageLedgerEvents -Path $resolvedPath)
        $newJson = $Event | ConvertTo-Json -Depth 32 -Compress
        $sameIdentity = @($records | Where-Object {
            [string]$_.event.event_id -ceq [string]$Event.event_id -or
            [string]$_.event.source_event_id -ceq [string]$Event.source_event_id
        })
        if ($sameIdentity.Count -gt 0) {
            if ($sameIdentity.Count -eq 1) {
                if (
                    [string]$sameIdentity[0].event.event_id -ceq
                        [string]$Event.event_id -and
                    [string]$sameIdentity[0].event.source_event_id -ceq
                        [string]$Event.source_event_id -and
                    [string]$sameIdentity[0].canonical_json -ceq $newJson
                ) {
                    return [pscustomobject][ordered]@{
                        status = 'replayed'
                        event_id = [string]$Event.event_id
                    }
                }
            }
            throw 'Usage event replay conflicts with the durable ledger.'
        }

        $lines = @(
            foreach ($record in $records) {
                [string]$record.canonical_json
            }
            $newJson
        )
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(
            ($lines -join "`n")
        )
        if ($bytes.Length -gt $script:maximumLedgerBytes) {
            throw 'Generated usage ledger exceeds its size limit.'
        }
        $temporary = Join-Path (Split-Path -Parent $resolvedPath) (
            ".write-$([Guid]::NewGuid().ToString('N')).tmp"
        )
        try {
            $stream = [IO.FileStream]::new(
                $temporary,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None,
                4096,
                [IO.FileOptions]::WriteThrough
            )
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush($true)
            } finally {
                $stream.Dispose()
            }
            [IO.File]::Move($temporary, $resolvedPath, $true)
        } finally {
            if (Test-Path -LiteralPath $temporary -PathType Leaf) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
        return [pscustomobject][ordered]@{
            status = 'inserted'
            event_id = [string]$Event.event_id
        }
    } finally {
        $lock.Dispose()
    }
}

function Write-ProjectDCodexQuotaSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$SnapshotPath
    )

    Assert-UsageLedgerSchemaValue `
        -Value $Snapshot `
        -SchemaFileName 'codex-quota-snapshot.schema.json' `
        -Label 'Codex quota snapshot'
    $resolvedPath = Resolve-ProjectDUsageQuotaPath `
        -ProjectRoot $ProjectRoot `
        -SnapshotPath $SnapshotPath
    $resolvedRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $lockPath = "$resolvedPath.lock"
    if (Test-PathHasReparsePoint -Root $resolvedRoot -ResolvedPath $lockPath) {
        throw 'Quota snapshot lock path must not cross a reparse point.'
    }
    $lock = Enter-ProjectDUsageLedgerLock -Path $lockPath
    try {
        $newJson = $Snapshot | ConvertTo-Json -Depth 32 -Compress
        $status = 'inserted'
        if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
            $item = Get-Item -LiteralPath $resolvedPath -Force
            if ($item.Length -gt 1MB) {
                throw 'Existing quota snapshot exceeds its size limit.'
            }
            try {
                $existingText = $script:utf8.GetString(
                    [IO.File]::ReadAllBytes($resolvedPath)
                )
                $existing = $existingText | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw 'Existing quota snapshot is not valid UTF-8 JSON.'
            }
            Assert-UsageLedgerSchemaValue `
                -Value $existing `
                -SchemaFileName 'codex-quota-snapshot.schema.json' `
                -Label 'Existing Codex quota snapshot'
            if ($existingText -ceq $newJson) {
                return [pscustomobject][ordered]@{ status = 'replayed' }
            }
            $existingCaptured = ConvertTo-UsageLedgerUtcTimestamp `
                -Value $existing.captured_at -Label 'Existing CapturedAt'
            $newCaptured = ConvertTo-UsageLedgerUtcTimestamp `
                -Value $Snapshot.captured_at -Label 'CapturedAt'
            if ($newCaptured -lt $existingCaptured) {
                throw 'Quota snapshot update is older than the durable snapshot.'
            }
            if ($newCaptured -eq $existingCaptured) {
                throw 'Quota snapshot replay conflicts at the same capture time.'
            }
            $status = 'updated'
        }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($newJson)
        $temporary = Join-Path (Split-Path -Parent $resolvedPath) (
            ".write-$([Guid]::NewGuid().ToString('N')).tmp"
        )
        try {
            $stream = [IO.FileStream]::new(
                $temporary,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None,
                4096,
                [IO.FileOptions]::WriteThrough
            )
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush($true)
            } finally {
                $stream.Dispose()
            }
            [IO.File]::Move($temporary, $resolvedPath, $true)
        } finally {
            if (Test-Path -LiteralPath $temporary -PathType Leaf) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
        return [pscustomobject][ordered]@{ status = $status }
    } finally {
        $lock.Dispose()
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-ProjectDCodexUsageEvent',
    'ConvertTo-ProjectDCodexQuotaSnapshot',
    'Write-ProjectDUsageLedgerEvent',
    'Write-ProjectDCodexQuotaSnapshot'
)
