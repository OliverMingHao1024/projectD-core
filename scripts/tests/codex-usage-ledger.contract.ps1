[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$importPath = Join-Path $core 'scripts\codex-usage-import.ps1'
$quotaImportPath = Join-Path $core 'scripts\codex-quota-import.ps1'
$ledgerModulePath = Join-Path $core 'scripts\lib\UsageLedger.psm1'
$projectionSchemaPath = Join-Path $core (
    'evals\schemas\codex-usage-projection.schema.json'
)
$eventSchemaPath = Join-Path $core 'evals\schemas\usage-events.schema.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "codex-usage-ledger-$PID"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )
    $thrown = $false
    try { $null = & $Action } catch { $thrown = $true }
    Assert-True $thrown $Message
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    $Value | ConvertTo-Json -Depth 20 | Set-Content `
        -LiteralPath $Path -Encoding utf8 -NoNewline
}

function Read-LedgerEvents {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(
        Get-Content -LiteralPath $Path | ForEach-Object {
            $_ | ConvertFrom-Json
        }
    )
}

try {
    $governanceRoot = Join-Path $tempRoot '.local\governance'
    $captureRoot = Join-Path $tempRoot '.local\capture'
    $usageRoot = Join-Path $tempRoot '.local\usage'
    New-Item -ItemType Directory -Path @(
        $governanceRoot,
        $captureRoot,
        $usageRoot
    ) -Force | Out-Null

    $accountsPath = Join-Path $governanceRoot 'usage-account-profiles.json'
    $devicePath = Join-Path $governanceRoot 'usage-device.json'
    $accountReadPath = Join-Path $captureRoot 'codex-account-read.json'
    $projectionPath = Join-Path $captureRoot 'codex-turn.json'
    $ledgerPath = Join-Path $usageRoot 'codex-ledger.jsonl'

    Write-JsonFixture -Path $accountsPath -Value ([ordered]@{
        schema_version = 1
        accounts = @([ordered]@{
            provider = 'codex'
            account_id = 'acct_11111111111111111111111111111111'
            alias = 'personal-codex'
            aliases = @('codex-personal')
            email = 'codex@example.test'
        })
    })
    Write-JsonFixture -Path $devicePath -Value ([ordered]@{
        schema_version = 1
        device_id = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        environment = 'work'
    })
    Write-JsonFixture -Path $accountReadPath -Value ([ordered]@{
        id = 7
        result = [ordered]@{
            account = [ordered]@{
                type = 'chatgpt'
                email = 'codex@example.test'
                planType = 'pro'
            }
            requiresOpenaiAuth = $true
        }
    })
    $projection = [ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = '2026-08-28T01:00:01Z'
        occurred_at = '2026-08-28T01:00:00Z'
        turn_status = 'completed'
        thread_id = 'thread_1234'
        turn_id = 'turn_5678'
        model = 'gpt-5.6'
        usage = [ordered]@{
            input_tokens = 1000
            cached_input_tokens = 800
            output_tokens = 200
            reasoning_tokens = 75
            cache_creation_tokens = 12
        }
    }
    Write-JsonFixture -Path $projectionPath -Value $projection

    Assert-True (
        Test-Path -LiteralPath $importPath -PathType Leaf
    ) 'The Codex usage import entrypoint must exist.'
    Assert-True (
        Test-Path -LiteralPath $ledgerModulePath -PathType Leaf
    ) 'The usage ledger module must exist.'
    Assert-True (
        Test-Path -LiteralPath $projectionSchemaPath -PathType Leaf
    ) 'The Codex usage projection schema must exist.'
    Assert-True (
        Test-Json `
            -Json ($projection | ConvertTo-Json -Depth 20) `
            -SchemaFile $projectionSchemaPath `
            -ErrorAction Stop
    ) 'A completed Codex turn projection must conform to its schema.'

    $first = & $importPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $projectionPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -LedgerPath $ledgerPath | ConvertFrom-Json
    Assert-True (
        [string]$first.status -ceq 'inserted'
    ) 'The first completed Codex turn must be inserted.'

    $events = @(Read-LedgerEvents -Path $ledgerPath)
    Assert-True ($events.Count -eq 1) 'The ledger must contain one event.'
    $event = $events[0]
    Assert-True (
        Test-Json `
            -Json ($event | ConvertTo-Json -Depth 20) `
            -SchemaFile $eventSchemaPath `
            -ErrorAction Stop
    ) 'Every ledger line must conform to the canonical usage event schema.'
    Assert-True (
        [string]$event.provider -ceq 'codex' -and
        [string]$event.session_id -ceq 'thread_1234' -and
        [string]$event.turn_id -ceq 'turn_5678'
    ) 'The event must retain provider session and turn identity.'
    Assert-True (
        [string]$event.identity.verification_status -ceq 'verified' -and
        [string]$event.identity.account_id -ceq (
            'acct_11111111111111111111111111111111'
        ) -and
        [string]$event.identity.device_id -ceq (
            'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        ) -and
        [string]$event.identity.environment -ceq 'work'
    ) 'Every Codex event must bind a verified account and device snapshot.'
    Assert-True (
        [string]$event.model.status -ceq 'observed' -and
        [string]$event.model.value -ceq 'gpt-5.6' -and
        [long]$event.usage.input_tokens.value -eq 1000 -and
        [long]$event.usage.cached_input_tokens.value -eq 800 -and
        [long]$event.usage.output_tokens.value -eq 200 -and
        [long]$event.usage.reasoning_tokens.value -eq 75 -and
        [long]$event.usage.cache_creation_tokens.value -eq 12
    ) 'The ledger must preserve every provider-supplied Codex token field.'
    Assert-True (
        [string]$event.usage.estimated_cost_usd.status -ceq 'unavailable'
    ) 'Codex import must not invent cost estimates.'

    $ledgerJson = Get-Content -Raw -LiteralPath $ledgerPath
    Assert-True (
        $ledgerJson -notmatch (
            '(?i)prompt|response|tool.arguments|tool.output|email|rate.?limit|quota'
        )
    ) 'The raw ledger must exclude content, email, quota, and rate-limit data.'

    $replay = & $importPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $projectionPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -LedgerPath $ledgerPath | ConvertFrom-Json
    Assert-True (
        [string]$replay.status -ceq 'replayed' -and
        @(Read-LedgerEvents -Path $ledgerPath).Count -eq 1
    ) 'Replaying the same completed turn must not duplicate usage.'

    $conflict = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $conflict.usage.output_tokens = 201
    $conflictPath = Join-Path $captureRoot 'codex-turn-conflict.json'
    Write-JsonFixture -Path $conflictPath -Value $conflict
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $conflictPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $ledgerPath
    } 'A changed replay of the same turn must fail closed.'
    Assert-True (
        @(Read-LedgerEvents -Path $ledgerPath).Count -eq 1
    ) 'A conflicting replay must not alter the ledger.'

    $unsafe = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $unsafe.prompt = 'must-never-enter-the-ledger'
    $unsafePath = Join-Path $captureRoot 'codex-turn-unsafe.json'
    Write-JsonFixture -Path $unsafePath -Value $unsafe
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $unsafePath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $ledgerPath
    } 'Content-bearing collector projections must be rejected.'

    $sensitiveModel = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $sensitiveModel.turn_id = 'turn_sensitive_model'
    $sensitiveModel.model = 'ghp_abcdefghijklmnopqrstuvwxyz'
    $sensitiveModelPath = Join-Path $captureRoot 'sensitive-model.json'
    Write-JsonFixture -Path $sensitiveModelPath -Value $sensitiveModel
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $sensitiveModelPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $ledgerPath
    } 'Sensitive-looking metadata values must fail closed.'

    $quota = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $quota.rate_limits = @{ used_percent = 25 }
    $quota.turn_id = 'turn_quota'
    $quotaPath = Join-Path $captureRoot 'codex-turn-quota.json'
    Write-JsonFixture -Path $quotaPath -Value $quota
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $quotaPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $ledgerPath
    } 'Quota windows must not enter the local per-turn token ledger.'

    $unknownAccountPath = Join-Path $captureRoot 'unknown-account.json'
    Write-JsonFixture -Path $unknownAccountPath -Value ([ordered]@{
        account = [ordered]@{
            type = 'chatgpt'
            email = 'someone-else@example.test'
            planType = 'pro'
        }
        requiresOpenaiAuth = $true
    })
    $unknownProjection = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $unknownProjection.turn_id = 'turn_unknown_account'
    $unknownProjectionPath = Join-Path $captureRoot 'unknown-turn.json'
    Write-JsonFixture -Path $unknownProjectionPath -Value $unknownProjection
    $identityError = $null
    try {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $unknownProjectionPath `
            -AccountReadPath $unknownAccountPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $ledgerPath
    } catch {
        $identityError = $_.Exception.Message
    }
    Assert-True (
        -not [string]::IsNullOrWhiteSpace($identityError) -and
        $identityError -notmatch 'someone-else@example\.test'
    ) 'Unknown accounts must fail closed without echoing the observed email.'

    $outsideLedger = Join-Path $tempRoot 'codex-ledger.jsonl'
    $secondProjection = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $secondProjection.turn_id = 'turn_second'
    $secondPath = Join-Path $captureRoot 'codex-turn-second.json'
    Write-JsonFixture -Path $secondPath -Value $secondProjection
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $secondPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $outsideLedger
    } 'Raw ledger output must stay inside .local/usage.'

    $second = & $importPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $secondPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -LedgerPath $ledgerPath | ConvertFrom-Json
    Assert-True (
        [string]$second.status -ceq 'inserted' -and
        @(Read-LedgerEvents -Path $ledgerPath).Count -eq 2
    ) 'A distinct completed turn must append exactly one event.'

    $quotaProjectionPath = Join-Path $captureRoot 'codex-quota.json'
    $quotaSnapshotPath = Join-Path $usageRoot 'codex-quota-snapshot.json'
    Write-JsonFixture -Path $quotaProjectionPath -Value ([ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = '2026-08-28T01:05:00Z'
        windows = @(
            [ordered]@{
                limit_id = 'codex'
                window = 'primary'
                used_percent = 22
                window_duration_minutes = 300
                resets_at = 1787882400
            }
            [ordered]@{
                limit_id = 'codex'
                window = 'secondary'
                used_percent = 41
                window_duration_minutes = 10080
                resets_at = 1788487200
            }
        )
    })
    Assert-True (
        Test-Path -LiteralPath $quotaImportPath -PathType Leaf
    ) 'The separate Codex quota import entrypoint must exist.'
    $quotaResult = & $quotaImportPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $quotaProjectionPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -SnapshotPath $quotaSnapshotPath | ConvertFrom-Json
    Assert-True (
        [string]$quotaResult.status -ceq 'inserted' -and
        (Test-Path -LiteralPath $quotaSnapshotPath -PathType Leaf)
    ) 'Official quota windows must be written to a separate snapshot.'
    $quotaSnapshot = Get-Content -Raw -LiteralPath $quotaSnapshotPath |
        ConvertFrom-Json
    Assert-True (
        [string]$quotaSnapshot.provider -ceq 'codex' -and
        [string]$quotaSnapshot.identity.verification_status -ceq 'verified' -and
        [string]$quotaSnapshot.identity.account_id -ceq (
            'acct_11111111111111111111111111111111'
        ) -and
        @($quotaSnapshot.windows).Count -eq 2
    ) 'Quota snapshots must retain verified identity and official windows.'
    Assert-True (
        (Get-Content -Raw -LiteralPath $quotaSnapshotPath) -notmatch (
            '(?i)prompt|response|tool.arguments|tool.output|email|input_tokens|output_tokens'
        )
    ) 'Quota snapshots must exclude content and per-turn token diagnostics.'
    Assert-True (
        @(Read-LedgerEvents -Path $ledgerPath).Count -eq 2
    ) 'Saving quota windows must not modify the per-turn token ledger.'
    $quotaReplay = & $quotaImportPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $quotaProjectionPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -SnapshotPath $quotaSnapshotPath | ConvertFrom-Json
    Assert-True (
        [string]$quotaReplay.status -ceq 'replayed'
    ) 'Replaying the same quota projection must not rewrite the snapshot.'

    $newerQuota = [ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = '2026-08-28T01:06:00Z'
        windows = @([ordered]@{
            limit_id = 'codex'
            window = 'primary'
            used_percent = 23
            window_duration_minutes = 300
            resets_at = 1787882400
        })
    }
    $newerQuotaPath = Join-Path $captureRoot 'codex-quota-newer.json'
    Write-JsonFixture -Path $newerQuotaPath -Value $newerQuota
    $quotaUpdate = & $quotaImportPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $newerQuotaPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -SnapshotPath $quotaSnapshotPath | ConvertFrom-Json
    Assert-True (
        [string]$quotaUpdate.status -ceq 'updated'
    ) 'A newer official quota snapshot must replace the previous snapshot.'
    Assert-Throws {
        & $quotaImportPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $quotaProjectionPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -SnapshotPath $quotaSnapshotPath
    } 'An older quota projection must not overwrite a newer snapshot.'
    $sameTimeConflict = $newerQuota | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $sameTimeConflict.windows[0].used_percent = 24
    $sameTimeConflictPath = Join-Path $captureRoot (
        'codex-quota-same-time-conflict.json'
    )
    Write-JsonFixture -Path $sameTimeConflictPath -Value $sameTimeConflict
    Assert-Throws {
        & $quotaImportPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $sameTimeConflictPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -SnapshotPath $quotaSnapshotPath
    } 'Different quota data at the same capture time must fail closed.'
    $durableQuota = Get-Content -Raw -LiteralPath $quotaSnapshotPath |
        ConvertFrom-Json
    Assert-True (
        [int]$durableQuota.windows[0].used_percent -eq 23
    ) 'Rejected quota updates must not alter the durable snapshot.'

    $tamperedLedgerPath = Join-Path $usageRoot 'tampered-ledger.jsonl'
    $tamperedEvent = $event | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $tamperedEvent.identity.verification_status = 'unknown'
    $tamperedEvent.identity.account_id = $null
    $tamperedEvent.identity.account_alias = $null
    $tamperedEvent | ConvertTo-Json -Depth 20 -Compress | Set-Content `
        -LiteralPath $tamperedLedgerPath -Encoding utf8 -NoNewline
    Assert-True (
        Test-Json `
            -Json (Get-Content -Raw -LiteralPath $tamperedLedgerPath) `
            -SchemaFile $eventSchemaPath -ErrorAction Stop
    ) 'The tampered fixture must remain schema-valid for the invariant test.'
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $secondPath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $tamperedLedgerPath
    } 'A schema-valid ledger with an unverified identity must fail closed.'

    $gitignore = Get-Content -Raw -LiteralPath (Join-Path $core '.gitignore')
    Assert-True (
        @($gitignore -split "`r?`n") -ccontains '.local/'
    ) 'The repository must ignore the entire local usage data root.'
    $implementationText = @(
        Get-Content -Raw -LiteralPath $importPath
        Get-Content -Raw -LiteralPath $quotaImportPath
        Get-Content -Raw -LiteralPath $ledgerModulePath
    ) -join "`n"
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?(?:codex|claude)\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'Usage ingestion must not launch a model or call a provider endpoint.'

    Write-Output 'CODEX_USAGE_LEDGER_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
