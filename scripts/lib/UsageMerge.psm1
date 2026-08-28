Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'GovernanceCommon.psm1') -Force

$script:utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:lockTimeout = [TimeSpan]::FromSeconds(10)
$script:metricNames = @(
    'input_tokens', 'cached_input_tokens', 'output_tokens',
    'reasoning_tokens', 'cache_creation_tokens', 'estimated_cost_usd'
)

function Get-UsageMergeSchemaPath {
    param([Parameter(Mandatory)][string]$SchemaFileName)
    $resolved = Join-Path $PSScriptRoot "..\..\evals\schemas\$SchemaFileName"
    $resolved = [IO.Path]::GetFullPath($resolved)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Canonical schema is missing: $SchemaFileName"
    }
    return $resolved
}

function Assert-UsageMergeSchemaValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaFileName,
        [Parameter(Mandatory)][string]$Label
    )
    $schemaPath = Get-UsageMergeSchemaPath -SchemaFileName $SchemaFileName
    try {
        $json = $Value | ConvertTo-Json -Depth 32
        $valid = Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop
        if (-not $valid) { throw 'JSON Schema validation returned false.' }
    } catch {
        throw "$Label does not conform to its canonical schema."
    }
}

function ConvertTo-UsageMergeUtcTimestamp {
    <#
    ConvertFrom-Json auto-detects ISO 8601 strings and returns them as
    culture-aware [DateTime] values, not strings. Casting one of those
    with a bare [string] cast then formats it using the current
    culture (e.g. "08/01/2026 00:00:00"), silently corrupting the
    canonical UTC ISO-8601 representation. Route every date-time field
    that may have crossed a JSON round-trip through this instead.
    #>
    param([Parameter(Mandatory)]$Value)
    return ([DateTimeOffset]$Value).ToUniversalTime().ToString('o')
}

function Get-ProjectDUsageBatchDigest {
    param([Parameter(Mandatory)]$Batch)
    $canonical = $Batch | ConvertTo-Json -Depth 32 -Compress
    return Get-TextSha256 -Text $canonical
}

function Read-ProjectDUsageMergeState {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            schema_version = 1
            updated_at = [DateTimeOffset]::UnixEpoch.ToString('o')
            consumed_batches = @()
            totals = @()
        }
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt 4MB) {
        throw 'Usage merge state exceeds its size limit.'
    }
    try {
        $json = $script:utf8.GetString([IO.File]::ReadAllBytes($Path))
        $state = $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw 'Usage merge state is not valid UTF-8 JSON.'
    }
    Assert-UsageMergeSchemaValue `
        -Value $state `
        -SchemaFileName 'usage-merge-state.schema.json' `
        -Label 'Usage merge state'
    return $state
}

function Get-UsageMergeRowKey {
    param([Parameter(Mandatory)]$Row)
    return (
        [string]$Row.alias + "`0" + [string]$Row.provider + "`0" +
        [string]$Row.model + "`0" + [string]$Row.device_id + "`0" +
        [string]$Row.environment + "`0" +
        (ConvertTo-UsageMergeUtcTimestamp $Row.period.start) + "`0" +
        (ConvertTo-UsageMergeUtcTimestamp $Row.period.end)
    )
}

function Merge-ProjectDUsageExportBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Batch,
        [Parameter(Mandatory)][string]$MergedAt
    )

    Assert-UsageMergeSchemaValue `
        -Value $Batch `
        -SchemaFileName 'usage-export-batch.schema.json' `
        -Label 'Usage export batch'

    $digest = Get-ProjectDUsageBatchDigest -Batch $Batch
    $alreadyConsumed = @(
        $State.consumed_batches | Where-Object {
            [string]$_.batch_digest -ceq $digest
        }
    )
    if ($alreadyConsumed.Count -gt 0) {
        return [pscustomobject][ordered]@{
            state = $State
            status = 'replayed'
        }
    }
    if (@($Batch.rows).Count -eq 0) {
        return [pscustomobject][ordered]@{
            state = $State
            status = 'empty'
        }
    }
    $batchDeviceIds = @(
        @($Batch.rows) | ForEach-Object { [string]$_.device_id } |
            Select-Object -Unique
    )
    if ($batchDeviceIds.Count -ne 1) {
        throw (
            'A single export batch must originate from exactly one device; ' +
            'merge cannot trust a batch spanning multiple device_id values.'
        )
    }
    $batchEnvironments = @(
        @($Batch.rows) | ForEach-Object { [string]$_.environment } |
            Select-Object -Unique
    )
    if ($batchEnvironments.Count -ne 1) {
        throw (
            'A single export batch must originate from exactly one ' +
            'environment; merge cannot trust a batch spanning multiple ' +
            'environment values.'
        )
    }

    function New-UsageMergeBucket {
        param($Row)
        $sums = [ordered]@{}
        foreach ($name in $script:metricNames) {
            $metric = $Row.$name
            $sums[$name] = if (
                $null -ne $metric -and [string]$metric.status -ceq 'observed'
            ) { [decimal]$metric.value } else { $null }
        }
        return [pscustomobject][ordered]@{
            alias = [string]$Row.alias
            provider = [string]$Row.provider
            model = [string]$Row.model
            device_id = [string]$Row.device_id
            environment = [string]$Row.environment
            period = [pscustomobject][ordered]@{
                start = ConvertTo-UsageMergeUtcTimestamp $Row.period.start
                end = ConvertTo-UsageMergeUtcTimestamp $Row.period.end
            }
            run_count = [long]$Row.run_count
            sums = $sums
        }
    }

    $rowIndex = [ordered]@{}
    foreach ($row in @($State.totals)) {
        $rowIndex[(Get-UsageMergeRowKey $row)] = New-UsageMergeBucket -Row $row
    }

    foreach ($sourceRow in @($Batch.rows)) {
        $row = $sourceRow | Select-Object *, @{
            Name = 'period'; Expression = { $Batch.period }
        } -ExcludeProperty period
        $key = Get-UsageMergeRowKey $row
        if (-not $rowIndex.Contains($key)) {
            $emptyRow = [pscustomobject][ordered]@{
                alias = $row.alias
                provider = $row.provider
                model = $row.model
                device_id = $row.device_id
                environment = $row.environment
                period = $row.period
                run_count = 0
            }
            foreach ($name in $script:metricNames) {
                $emptyRow | Add-Member -NotePropertyName $name -NotePropertyValue (
                    [pscustomobject][ordered]@{ status = 'unavailable'; value = $null }
                )
            }
            $rowIndex[$key] = New-UsageMergeBucket -Row $emptyRow
        }
        $entry = $rowIndex[$key]
        $entry.run_count += [long]$row.run_count
        foreach ($name in $script:metricNames) {
            $metric = $row.$name
            if ([string]$metric.status -ceq 'observed') {
                $current = $entry.sums[$name]
                $entry.sums[$name] = (
                    [decimal]($null -eq $current ? 0 : $current) +
                    [decimal]$metric.value
                )
            }
        }
    }

    $totals = @(
        $rowIndex.Values |
            Sort-Object -Property @(
                'alias', 'provider', 'model', 'device_id', 'environment',
                @{ Expression = { $_.period.start } },
                @{ Expression = { $_.period.end } }
            ) |
            ForEach-Object {
                $entry = $_
                $out = [ordered]@{
                    alias = $entry.alias
                    provider = $entry.provider
                    model = $entry.model
                    device_id = $entry.device_id
                    environment = $entry.environment
                    period = $entry.period
                    run_count = $entry.run_count
                }
                foreach ($name in $script:metricNames) {
                    $value = $entry.sums[$name]
                    $out[$name] = if ($null -eq $value) {
                        [pscustomobject][ordered]@{
                            status = 'unavailable'; value = $null
                        }
                    } else {
                        [pscustomobject][ordered]@{
                            status = 'observed'; value = $value
                        }
                    }
                }
                [pscustomobject]$out
            }
    )

    $consumed = @($State.consumed_batches) + @(
        [pscustomobject][ordered]@{
            batch_digest = $digest
            device_id = $batchDeviceIds[0]
            environment = $batchEnvironments[0]
            period = $Batch.period
            source_version = [string]$Batch.source_version
            merged_at = $MergedAt
        }
    )

    $newState = [pscustomobject][ordered]@{
        schema_version = 1
        updated_at = $MergedAt
        consumed_batches = $consumed
        totals = $totals
    }
    Assert-UsageMergeSchemaValue `
        -Value $newState `
        -SchemaFileName 'usage-merge-state.schema.json' `
        -Label 'Usage merge state'
    return [pscustomobject][ordered]@{
        state = $newState
        status = 'merged'
    }
}

function Resolve-ProjectDUsageMergeStatePath {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$StatePath
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $mergeRoot = [IO.Path]::GetFullPath((
        Join-Path $root '.local\usage\merge'
    ))
    $candidate = if ([IO.Path]::IsPathRooted($StatePath)) {
        [IO.Path]::GetFullPath($StatePath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $StatePath))
    }
    $mergePrefix = $mergeRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith(
        $mergePrefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Usage merge state must stay inside ProjectRoot/.local/usage/merge.'
    }
    if ([IO.Path]::GetExtension($candidate) -cne '.json') {
        throw 'Usage merge state must use the .json extension.'
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $candidate) {
        throw 'Usage merge state path must not cross a reparse point.'
    }
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $candidate
    ) -Force | Out-Null
    return $candidate
}

function Write-ProjectDUsageMergeState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$StatePath
    )

    $resolved = Resolve-ProjectDUsageMergeStatePath `
        -ProjectRoot $ProjectRoot -StatePath $StatePath
    $lockPath = "$resolved.lock"
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $lock = $null
    do {
        try {
            $lock = [IO.FileStream]::new(
                $lockPath, [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite, [IO.FileShare]::None
            )
        } catch [IO.IOException] {
            if ($stopwatch.Elapsed -ge $script:lockTimeout) {
                throw 'Timed out waiting for the usage merge state writer.'
            }
            Start-Sleep -Milliseconds 50
        }
    } while ($null -eq $lock)
    try {
        $json = $State | ConvertTo-Json -Depth 32
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
        $temporary = "$resolved.$([Guid]::NewGuid().ToString('N')).tmp"
        try {
            [IO.File]::WriteAllBytes($temporary, $bytes)
            [IO.File]::Move($temporary, $resolved, $true)
        } finally {
            if (Test-Path -LiteralPath $temporary -PathType Leaf) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
    } finally {
        $lock.Dispose()
    }
    return $resolved
}

Export-ModuleMember -Function @(
    'Get-ProjectDUsageBatchDigest',
    'Read-ProjectDUsageMergeState',
    'Merge-ProjectDUsageExportBatch',
    'Resolve-ProjectDUsageMergeStatePath',
    'Write-ProjectDUsageMergeState'
)
