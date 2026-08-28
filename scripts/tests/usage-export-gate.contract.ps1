[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runPath = Join-Path $core 'scripts\usage-export-run.ps1'
$gateModulePath = Join-Path $core 'scripts\lib\UsageExportGate.psm1'
$ledgerModulePath = Join-Path $core 'scripts\lib\UsageLedger.psm1'
$batchSchemaPath = Join-Path $core 'evals\schemas\usage-export-batch.schema.json'
$policySchemaPath = Join-Path $core (
    'evals\schemas\usage-export-policy.schema.json'
)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "usage-export-gate-$PID"

Import-Module $gateModulePath -Force -ErrorAction Stop
Import-Module $ledgerModulePath -Force -ErrorAction Stop

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
    try { $null = & $Action 2>$null } catch { $thrown = $true }
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

function New-VerifiedIdentityFixture {
    param(
        [string]$Provider = 'codex',
        [string]$AccountId = 'acct_11111111111111111111111111111111',
        [string]$Alias = 'personal-codex',
        [string]$DeviceId = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    )
    return [pscustomobject][ordered]@{
        schema_version = 1
        captured_at = '2026-08-28T01:00:00Z'
        provider = $Provider
        verification_status = 'verified'
        account_id = $AccountId
        account_alias = $Alias
        device_id = $DeviceId
        environment = 'work'
        billing_source = 'subscription'
        plan_type = [pscustomobject][ordered]@{
            status = 'observed'
            value = 'pro'
        }
    }
}

function New-UsageEventFixture {
    param(
        [Parameter(Mandatory)][string]$EventId,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$TurnId,
        [Parameter(Mandatory)][string]$OccurredAt,
        [Parameter(Mandatory)]$Identity,
        [string]$Model = 'gpt-5.6',
        [int]$InputTokens = 100,
        [int]$OutputTokens = 20
    )
    return [pscustomobject][ordered]@{
        schema_version = 1
        event_id = $EventId
        source_event_id = $EventId
        session_id = $SessionId
        turn_id = $TurnId
        occurred_at = $OccurredAt
        provider = [string]$Identity.provider
        identity = $Identity
        model = [pscustomobject][ordered]@{
            status = 'observed'
            value = $Model
        }
        usage = [pscustomobject][ordered]@{
            input_tokens = [pscustomobject][ordered]@{
                status = 'observed'; value = $InputTokens
            }
            cached_input_tokens = [pscustomobject][ordered]@{
                status = 'unavailable'; value = $null
            }
            output_tokens = [pscustomobject][ordered]@{
                status = 'observed'; value = $OutputTokens
            }
            reasoning_tokens = [pscustomobject][ordered]@{
                status = 'unavailable'; value = $null
            }
            cache_creation_tokens = [pscustomobject][ordered]@{
                status = 'unavailable'; value = $null
            }
            estimated_cost_usd = [pscustomobject][ordered]@{
                status = 'unavailable'; value = $null
            }
        }
    }
}

function Write-LedgerFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][array]$Events
    )
    $lines = @($Events | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress })
    Set-Content -LiteralPath $Path -Value ($lines -join "`n") `
        -Encoding utf8 -NoNewline
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Assert-True (
        Test-Path -LiteralPath $runPath -PathType Leaf
    ) 'The usage export run entrypoint must exist.'
    Assert-True (
        Test-Path -LiteralPath $gateModulePath -PathType Leaf
    ) 'The usage export gate module must exist.'
    Assert-True (
        Test-Path -LiteralPath $batchSchemaPath -PathType Leaf
    ) 'The usage export batch schema must exist.'
    Assert-True (
        Test-Path -LiteralPath $policySchemaPath -PathType Leaf
    ) 'The usage export policy schema must exist.'

    # --- unit-level canary coverage on the content scanner itself ---
    Assert-True (
        -not (Test-ProjectDUsageExportContentSafe 'contact me at someone@example.test')
    ) 'The canary scanner must flag an email address.'
    Assert-True (
        -not (Test-ProjectDUsageExportContentSafe (
            'token ghp_abcdefghijklmnopqrstuvwxyz0123456789'
        ))
    ) 'The canary scanner must flag a credential-like token.'
    Assert-True (
        -not (Test-ProjectDUsageExportContentSafe 'C:\\Users\\oliver\\secret')
    ) 'The canary scanner must flag a local Windows path.'
    Assert-True (
        -not (Test-ProjectDUsageExportContentSafe '/home/oliver/workspaces/acme')
    ) 'The canary scanner must flag a local POSIX path and workspace name.'
    Assert-True (
        -not (Test-ProjectDUsageExportContentSafe (
            'github.com/acme-corp/private-repo'
        ))
    ) 'The canary scanner must flag a repository URL and embedded company name.'
    Assert-True (
        Test-ProjectDUsageExportContentSafe 'personal-codex claude gpt-5.6 42'
    ) 'The canary scanner must not flag ordinary safe row content.'

    # --- policy: local-only default when no policy file exists ---
    $projectRootA = Join-Path $tempRoot 'proj-a'
    New-Item -ItemType Directory -Path (
        Join-Path $projectRootA '.local\usage'
    ) -Force | Out-Null
    $identityA = New-VerifiedIdentityFixture
    $ledgerA = Join-Path $projectRootA '.local\usage\codex-ledger.jsonl'
    Write-LedgerFixture -Path $ledgerA -Events @(
        (New-UsageEventFixture `
            -EventId 'evt_a1' -SessionId 'thread_a1' -TurnId 'turn_a1' `
            -OccurredAt '2026-08-01T00:00:00Z' -Identity $identityA)
    )
    $defaultPolicy = Read-ProjectDUsageExportPolicy -Path (
        Join-Path $projectRootA '.local\governance\usage-export-policy.json'
    )
    Assert-True (
        -not (Test-ProjectDUsageExportAllowed -Policy $defaultPolicy)
    ) 'A missing export policy must default to local-only.'
    Assert-Throws {
        & $runPath `
            -ProjectRoot $projectRootA `
            -PeriodStart '2026-08-01T00:00:00Z' `
            -PeriodEnd '2026-09-01T00:00:00Z'
    } 'Export must fail closed when no policy explicitly allows it.'
    $exportDirA = Join-Path $projectRootA '.local\usage\export'
    $quarantineDirA = Join-Path $exportDirA 'quarantine'
    Assert-True (
        (Test-Path -LiteralPath $quarantineDirA -PathType Container) -and
        @(Get-ChildItem -LiteralPath $quarantineDirA -Filter '*.json').Count -eq 1
    ) 'A rejected batch must be quarantined instead of exported.'
    Assert-True (
        @(Get-ChildItem -LiteralPath $exportDirA -Filter 'usage-export-*.json' `
            -File -ErrorAction SilentlyContinue).Count -eq 0
    ) 'No exportable batch may exist when policy denies export.'
    $quarantineRecordA = Get-Content -Raw -LiteralPath (
        @(Get-ChildItem -LiteralPath $quarantineDirA -Filter '*.json')[0].FullName
    ) | ConvertFrom-Json
    Assert-True (
        $quarantineRecordA.reason -notmatch (
            '(?i)acct_1111|personal-codex@|thread_a1'
        )
    ) 'Quarantine records must not echo raw identity or session values.'

    # --- policy: explicit export_allowed:false is equivalent to local-only ---
    $policyPathA = Join-Path $projectRootA '.local\governance\usage-export-policy.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $policyPathA) `
        -Force | Out-Null
    Write-JsonFixture -Path $policyPathA -Value ([ordered]@{
        schema_version = 1
        export_allowed = $false
        policy_version = 'work-laptop-v1'
    })
    Assert-Throws {
        & $runPath `
            -ProjectRoot $projectRootA `
            -PeriodStart '2026-08-01T00:00:00Z' `
            -PeriodEnd '2026-09-01T00:00:00Z'
    } 'An explicit export_allowed:false policy must still fail closed.'

    # --- policy: explicit allow produces a valid, de-identified batch ---
    Write-JsonFixture -Path $policyPathA -Value ([ordered]@{
        schema_version = 1
        export_allowed = $true
        policy_version = 'home-desktop-v1'
    })
    $secondEventA = New-UsageEventFixture `
        -EventId 'evt_a2' -SessionId 'thread_a1' -TurnId 'turn_a2' `
        -OccurredAt '2026-08-02T00:00:00Z' -Identity $identityA `
        -InputTokens 50 -OutputTokens 10
    Write-LedgerFixture -Path $ledgerA -Events @(
        (New-UsageEventFixture `
            -EventId 'evt_a1' -SessionId 'thread_a1' -TurnId 'turn_a1' `
            -OccurredAt '2026-08-01T00:00:00Z' -Identity $identityA),
        $secondEventA
    )
    $runOutput = & $runPath `
        -ProjectRoot $projectRootA `
        -PeriodStart '2026-08-01T00:00:00Z' `
        -PeriodEnd '2026-09-01T00:00:00Z' | ConvertFrom-Json
    Assert-True (
        [string]$runOutput.status -ceq 'exported' -and
        [int]$runOutput.rows -eq 1
    ) 'Two events sharing alias/provider/model must aggregate into one row.'
    $batchJson = Get-Content -Raw -LiteralPath ([string]$runOutput.path)
    Assert-True (
        Test-Json -Json $batchJson -SchemaFile $batchSchemaPath -ErrorAction Stop
    ) 'The exported batch must conform to its canonical schema.'
    $batch = $batchJson | ConvertFrom-Json
    $row = $batch.rows[0]
    Assert-True (
        [string]$row.alias -ceq 'personal-codex' -and
        [string]$row.provider -ceq 'codex' -and
        [string]$row.model -ceq 'gpt-5.6' -and
        [int]$row.run_count -eq 2 -and
        [long]$row.input_tokens.value -eq 150 -and
        [long]$row.output_tokens.value -eq 30 -and
        [string]$row.cached_input_tokens.status -ceq 'unavailable'
    ) 'The aggregated row must sum observed metrics and preserve unavailable status.'
    Assert-True (
        $batchJson -notmatch (
            '(?i)acct_1111|thread_a1|turn_a1|turn_a2|dev_aaaa|@example|C:\\\\|/home/'
        )
    ) (
        'The exported batch must exclude account_id, session/turn identifiers, ' +
        'device_id, email, and local paths.'
    )

    # --- fail-closed: an unverified identity in the ledger must be rejected ---
    $projectRootB = Join-Path $tempRoot 'proj-b'
    New-Item -ItemType Directory -Path (
        Join-Path $projectRootB '.local\governance'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $projectRootB '.local\usage'
    ) -Force | Out-Null
    Write-JsonFixture -Path (
        Join-Path $projectRootB '.local\governance\usage-export-policy.json'
    ) -Value ([ordered]@{
        schema_version = 1
        export_allowed = $true
        policy_version = 'home-desktop-v1'
    })
    $unknownIdentity = New-VerifiedIdentityFixture
    $unknownIdentity.verification_status = 'unknown'
    $unknownIdentity.account_id = $null
    $unknownIdentity.account_alias = $null
    $ledgerB = Join-Path $projectRootB '.local\usage\codex-ledger.jsonl'
    Write-LedgerFixture -Path $ledgerB -Events @(
        (New-UsageEventFixture `
            -EventId 'evt_b1' -SessionId 'thread_b1' -TurnId 'turn_b1' `
            -OccurredAt '2026-08-01T00:00:00Z' -Identity $unknownIdentity)
    )
    Assert-Throws {
        & $runPath `
            -ProjectRoot $projectRootB `
            -PeriodStart '2026-08-01T00:00:00Z' `
            -PeriodEnd '2026-09-01T00:00:00Z'
    } 'An unverified identity must be rejected and quarantined, not exported.'

    # --- fail-closed: a schema-valid but URL-smuggling model must be caught ---
    # by the content canary, since the model pattern otherwise permits '.', '/'.
    $projectRootC = Join-Path $tempRoot 'proj-c'
    New-Item -ItemType Directory -Path (
        Join-Path $projectRootC '.local\governance'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $projectRootC '.local\usage'
    ) -Force | Out-Null
    Write-JsonFixture -Path (
        Join-Path $projectRootC '.local\governance\usage-export-policy.json'
    ) -Value ([ordered]@{
        schema_version = 1
        export_allowed = $true
        policy_version = 'home-desktop-v1'
    })
    $identityC = New-VerifiedIdentityFixture
    $smugglingEvent = New-UsageEventFixture `
        -EventId 'evt_c1' -SessionId 'thread_c1' -TurnId 'turn_c1' `
        -OccurredAt '2026-08-01T00:00:00Z' -Identity $identityC `
        -Model 'github.com/acme-corp/private-repo'
    Assert-True (
        [string]$smugglingEvent.model.value -cmatch (
            '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
        )
    ) (
        'The smuggling fixture must remain schema-pattern-valid to prove the ' +
        'canary, not the schema, is what catches it.'
    )
    $ledgerC = Join-Path $projectRootC '.local\usage\codex-ledger.jsonl'
    Write-LedgerFixture -Path $ledgerC -Events @($smugglingEvent)
    Assert-Throws {
        & $runPath `
            -ProjectRoot $projectRootC `
            -PeriodStart '2026-08-01T00:00:00Z' `
            -PeriodEnd '2026-09-01T00:00:00Z'
    } 'A repository-URL-shaped model value must fail the content canary scan.'

    # --- determinism and no model/network calls ---
    $implementationText = @(
        Get-Content -Raw -LiteralPath $runPath
        Get-Content -Raw -LiteralPath $gateModulePath
    ) -join "`n"
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?(?:codex|claude)\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'Usage export must not launch a model or call a provider endpoint.'
    Assert-True (
        (Get-Content -Raw -LiteralPath $runPath) -notmatch '(?i)Get-Random'
    ) 'Aggregation and gating must not depend on non-deterministic values.'

    Write-Output 'USAGE_EXPORT_GATE_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
