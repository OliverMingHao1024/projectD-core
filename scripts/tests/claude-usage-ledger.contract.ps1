[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$importPath = Join-Path $core 'scripts\claude-usage-import.ps1'
$ledgerModulePath = Join-Path $core 'scripts\lib\UsageLedger.psm1'
$projectionSchemaPath = Join-Path $core (
    'evals\schemas\claude-usage-projection.schema.json'
)
$eventSchemaPath = Join-Path $core 'evals\schemas\usage-events.schema.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "claude-usage-ledger-$PID"

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
    $accountReadPath = Join-Path $captureRoot 'claude-account-read.json'
    $projectionPath = Join-Path $captureRoot 'claude-turn.json'
    $ledgerPath = Join-Path $usageRoot 'claude-ledger.jsonl'

    Write-JsonFixture -Path $accountsPath -Value ([ordered]@{
        schema_version = 1
        accounts = @([ordered]@{
            provider = 'claude'
            account_id = 'acct_22222222222222222222222222222222'
            alias = 'work-claude'
            aliases = @('claude-work')
            email = 'claude@example.test'
        })
    })
    Write-JsonFixture -Path $devicePath -Value ([ordered]@{
        schema_version = 1
        device_id = 'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        environment = 'work'
    })
    Write-JsonFixture -Path $accountReadPath -Value ([ordered]@{
        auth = [ordered]@{
            loggedIn = $true
            authMethod = 'claude.ai'
            apiProvider = 'firstParty'
            subscriptionType = 'team'
            email = 'claude@example.test'
        }
        environmentState = [ordered]@{
            apiBilling = $false
            thirdParty = $false
        }
    })
    $projection = [ordered]@{
        schema_version = 1
        source = 'claude-code-transcript'
        captured_at = '2026-08-28T02:00:01Z'
        occurred_at = '2026-08-28T02:00:00Z'
        session_id = '09ea4d09-33c8-4c08-b329-aeec98199451'
        turn_id = 'e7b209ce-201c-4d30-a156-0a41fbe6db36'
        model = 'claude-sonnet-5'
        usage = [ordered]@{
            input_tokens = 2
            cached_input_tokens = 49178
            output_tokens = 258
            reasoning_tokens = 147
            cache_creation_tokens = 18326
        }
    }
    Write-JsonFixture -Path $projectionPath -Value $projection

    Assert-True (
        Test-Path -LiteralPath $importPath -PathType Leaf
    ) 'The Claude usage import entrypoint must exist.'
    Assert-True (
        Test-Path -LiteralPath $ledgerModulePath -PathType Leaf
    ) 'The usage ledger module must exist.'
    Assert-True (
        Test-Path -LiteralPath $projectionSchemaPath -PathType Leaf
    ) 'The Claude usage projection schema must exist.'
    Assert-True (
        Test-Json `
            -Json ($projection | ConvertTo-Json -Depth 20) `
            -SchemaFile $projectionSchemaPath `
            -ErrorAction Stop
    ) 'A completed Claude turn projection must conform to its schema.'

    $first = & $importPath `
        -ProjectRoot $tempRoot `
        -ProjectionPath $projectionPath `
        -AccountReadPath $accountReadPath `
        -AccountProfilesPath $accountsPath `
        -DeviceProfilePath $devicePath `
        -LedgerPath $ledgerPath | ConvertFrom-Json
    Assert-True (
        [string]$first.status -ceq 'inserted'
    ) 'The first completed Claude turn must be inserted.'

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
        [string]$event.provider -ceq 'claude' -and
        [string]$event.session_id -ceq (
            '09ea4d09-33c8-4c08-b329-aeec98199451'
        ) -and
        [string]$event.turn_id -ceq (
            'e7b209ce-201c-4d30-a156-0a41fbe6db36'
        )
    ) 'The event must retain provider session and turn identity.'
    Assert-True (
        [string]$event.identity.verification_status -ceq 'verified' -and
        [string]$event.identity.account_id -ceq (
            'acct_22222222222222222222222222222222'
        ) -and
        [string]$event.identity.device_id -ceq (
            'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        ) -and
        [string]$event.identity.environment -ceq 'work' -and
        [string]$event.identity.billing_source -ceq 'subscription'
    ) 'Every Claude event must bind a verified account and device snapshot.'
    Assert-True (
        [string]$event.model.status -ceq 'observed' -and
        [string]$event.model.value -ceq 'claude-sonnet-5' -and
        [long]$event.usage.input_tokens.value -eq 2 -and
        [long]$event.usage.cached_input_tokens.value -eq 49178 -and
        [long]$event.usage.output_tokens.value -eq 258 -and
        [long]$event.usage.reasoning_tokens.value -eq 147 -and
        [long]$event.usage.cache_creation_tokens.value -eq 18326
    ) 'The ledger must preserve every provider-supplied Claude token field.'
    Assert-True (
        [string]$event.usage.estimated_cost_usd.status -ceq 'unavailable'
    ) 'Claude import must not invent cost estimates.'

    $ledgerJson = Get-Content -Raw -LiteralPath $ledgerPath
    Assert-True (
        $ledgerJson -notmatch (
            '(?i)prompt|response|tool.arguments|tool.output|email|thinking|content'
        )
    ) 'The raw ledger must exclude content, email, and thinking-block data.'

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
    $conflict.usage.output_tokens = 259
    $conflictPath = Join-Path $captureRoot 'claude-turn-conflict.json'
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
    $unsafePath = Join-Path $captureRoot 'claude-turn-unsafe.json'
    Write-JsonFixture -Path $unsafePath -Value $unsafe
    Assert-Throws {
        & $importPath `
            -ProjectRoot $tempRoot `
            -ProjectionPath $unsafePath `
            -AccountReadPath $accountReadPath `
            -AccountProfilesPath $accountsPath `
            -DeviceProfilePath $devicePath `
            -LedgerPath $ledgerPath
    } 'Content-bearing transcript projections must be rejected.'

    $sensitiveModel = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $sensitiveModel.turn_id = 'sensitive-model-turn-0000000000000'
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

    $unknownAccountPath = Join-Path $captureRoot 'unknown-account.json'
    Write-JsonFixture -Path $unknownAccountPath -Value ([ordered]@{
        auth = [ordered]@{
            loggedIn = $true
            authMethod = 'claude.ai'
            apiProvider = 'firstParty'
            subscriptionType = 'team'
            email = 'someone-else@example.test'
        }
        environmentState = [ordered]@{
            apiBilling = $false
            thirdParty = $false
        }
    })
    $unknownProjection = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $unknownProjection.turn_id = 'unknown-account-turn-0000000000000'
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

    $outsideLedger = Join-Path $tempRoot 'claude-ledger.jsonl'
    $secondProjection = $projection | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $secondProjection.turn_id = 'second-turn-0000000000000000000000'
    $secondPath = Join-Path $captureRoot 'claude-turn-second.json'
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
        Get-Content -Raw -LiteralPath $ledgerModulePath
    ) -join "`n"
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?(?:codex|claude)\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'Usage ingestion must not launch a model or call a provider endpoint.'

    Write-Output 'CLAUDE_USAGE_LEDGER_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
