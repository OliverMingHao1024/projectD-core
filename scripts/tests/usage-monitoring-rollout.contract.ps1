[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$rolloutPath = Join-Path $core 'scripts\usage-monitoring-rollout.ps1'
$codexImportPath = Join-Path $core 'scripts\codex-usage-import.ps1'
$exportRunPath = Join-Path $core 'scripts\usage-export-run.ps1'
$mergeRunPath = Join-Path $core 'scripts\usage-merge-run.ps1'
$reportRunPath = Join-Path $core 'scripts\usage-report-run.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "usage-rollout-$PID"

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
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $Value | ConvertTo-Json -Depth 20 | Set-Content `
        -LiteralPath $Path -Encoding utf8 -NoNewline
}

$sharedAccountId = 'acct_33333333333333333333333333333333'
$sharedAlias = 'shared-codex'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    foreach ($script in @(
        $rolloutPath, $codexImportPath, $exportRunPath, $mergeRunPath, $reportRunPath
    )) {
        Assert-True (
            Test-Path -LiteralPath $script -PathType Leaf
        ) "Required rollout entrypoint must exist: $script"
    }

    ### Device A: work, local-only by default ###
    $deviceA = Join-Path $tempRoot 'device-a'
    New-Item -ItemType Directory -Path $deviceA -Force | Out-Null
    & $rolloutPath -Mode Apply -ProjectRoot $deviceA -Environment work | Out-Null
    $statusA = & $rolloutPath -Mode Check -ProjectRoot $deviceA | ConvertFrom-Json
    Assert-True (
        [bool]$statusA.device_profile.valid -and
        -not [bool]$statusA.export_allowed
    ) 'A freshly-applied device must default to local-only.'

    Write-JsonFixture -Path (
        Join-Path $deviceA '.local\governance\usage-account-profiles.json'
    ) -Value ([ordered]@{
        schema_version = 1
        accounts = @([ordered]@{
            provider = 'codex'
            account_id = $sharedAccountId
            alias = $sharedAlias
            aliases = @()
            email = 'shared@example.test'
        })
    })

    $captureA = Join-Path $deviceA '.local\capture'
    Write-JsonFixture -Path (Join-Path $captureA 'codex-account-read.json') -Value ([ordered]@{
        id = 1
        result = [ordered]@{
            account = [ordered]@{
                type = 'chatgpt'; email = 'shared@example.test'; planType = 'pro'
            }
            requiresOpenaiAuth = $true
        }
    })
    Write-JsonFixture -Path (Join-Path $captureA 'codex-turn.json') -Value ([ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = '2026-08-01T01:00:01Z'
        occurred_at = '2026-08-01T01:00:00Z'
        turn_status = 'completed'
        thread_id = 'thread_a1'
        turn_id = 'turn_a1'
        model = 'gpt-5.6'
        usage = [ordered]@{
            input_tokens = 200; cached_input_tokens = 0
            output_tokens = 40; reasoning_tokens = 10
        }
    })
    $ledgerA = Join-Path $deviceA '.local\usage\codex-ledger.jsonl'
    $insertedA = & $codexImportPath `
        -ProjectRoot $deviceA `
        -ProjectionPath (Join-Path $captureA 'codex-turn.json') `
        -AccountReadPath (Join-Path $captureA 'codex-account-read.json') `
        -LedgerPath $ledgerA | ConvertFrom-Json
    Assert-True (
        [string]$insertedA.status -ceq 'inserted'
    ) 'Device A must be able to capture usage into its own local ledger.'

    # Local-only device must never produce an exportable batch.
    Assert-Throws {
        & $exportRunPath `
            -ProjectRoot $deviceA `
            -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-02T00:00:00Z'
    } 'A work device with no explicit export policy must fail closed on export.'
    $quarantineDirA = Join-Path $deviceA '.local\usage\export\quarantine'
    Assert-True (
        (Test-Path -LiteralPath $quarantineDirA -PathType Container) -and
        @(Get-ChildItem -LiteralPath $quarantineDirA -Filter '*.json').Count -ge 1
    ) 'The denied export must be quarantined, not silently dropped.'
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $deviceA '.local\usage\export'
        ) -PathType Container) -or
        @(Get-ChildItem -LiteralPath (Join-Path $deviceA '.local\usage\export') `
            -Filter 'usage-export-*.json' -File -ErrorAction SilentlyContinue).Count -eq 0
    ) 'A local-only device must never produce an exportable batch file.'

    # A local report must still work entirely offline on device A's own ledger.
    $reportA = & $reportRunPath `
        -ProjectRoot $deviceA -Mode local -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-02T00:00:00Z' `
        -OutputPath (Join-Path $deviceA '.local\usage\reports\report.json') |
        ConvertFrom-Json
    Assert-True (
        [int]$reportA.rows -eq 1
    ) 'Local-only mode must still produce a usable single-device report.'

    # Failure isolation: an unknown-identity import must fail closed without
    # touching the ledger that already has good data, and without crashing
    # anything else in the pipeline.
    Write-JsonFixture -Path (Join-Path $captureA 'codex-account-read-unknown.json') -Value ([ordered]@{
        id = 2
        result = [ordered]@{
            account = [ordered]@{
                type = 'chatgpt'; email = 'someone-else@example.test'; planType = 'pro'
            }
            requiresOpenaiAuth = $true
        }
    })
    Write-JsonFixture -Path (Join-Path $captureA 'codex-turn-2.json') -Value ([ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = '2026-08-01T02:00:01Z'
        occurred_at = '2026-08-01T02:00:00Z'
        turn_status = 'completed'
        thread_id = 'thread_a1'
        turn_id = 'turn_a2'
        model = 'gpt-5.6'
        usage = [ordered]@{
            input_tokens = 1; cached_input_tokens = 0
            output_tokens = 1; reasoning_tokens = 0
        }
    })
    $ledgerCountBefore = @(Get-Content -LiteralPath $ledgerA).Count
    Assert-Throws {
        & $codexImportPath `
            -ProjectRoot $deviceA `
            -ProjectionPath (Join-Path $captureA 'codex-turn-2.json') `
            -AccountReadPath (Join-Path $captureA 'codex-account-read-unknown.json') `
            -LedgerPath $ledgerA
    } 'An unknown-account import must fail closed.'
    Assert-True (
        @(Get-Content -LiteralPath $ledgerA).Count -eq $ledgerCountBefore
    ) 'A failed import must not corrupt or partially write the existing ledger.'
    $diagnosticsPathA = Join-Path $deviceA (
        '.local\usage\diagnostics\identity-events.jsonl'
    )
    Assert-True (
        Test-Path -LiteralPath $diagnosticsPathA -PathType Leaf
    ) 'A failed identity resolution must still leave a diagnostic trace.'

    ### Device B: home, cross-device export explicitly allowed ###
    $deviceB = Join-Path $tempRoot 'device-b'
    New-Item -ItemType Directory -Path $deviceB -Force | Out-Null
    & $rolloutPath -Mode Apply -ProjectRoot $deviceB -Environment home -AllowExport |
        Out-Null
    $statusB = & $rolloutPath -Mode Check -ProjectRoot $deviceB | ConvertFrom-Json
    Assert-True (
        [bool]$statusB.export_allowed
    ) 'Apply -AllowExport must enable export on a home device.'

    Write-JsonFixture -Path (
        Join-Path $deviceB '.local\governance\usage-account-profiles.json'
    ) -Value ([ordered]@{
        schema_version = 1
        accounts = @([ordered]@{
            provider = 'codex'
            account_id = $sharedAccountId
            alias = $sharedAlias
            aliases = @()
            email = 'shared@example.test'
        })
    })
    $captureB = Join-Path $deviceB '.local\capture'
    Write-JsonFixture -Path (Join-Path $captureB 'codex-account-read.json') -Value ([ordered]@{
        id = 1
        result = [ordered]@{
            account = [ordered]@{
                type = 'chatgpt'; email = 'shared@example.test'; planType = 'pro'
            }
            requiresOpenaiAuth = $true
        }
    })
    Write-JsonFixture -Path (Join-Path $captureB 'codex-turn.json') -Value ([ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = '2026-08-01T05:00:01Z'
        occurred_at = '2026-08-01T05:00:00Z'
        turn_status = 'completed'
        thread_id = 'thread_b1'
        turn_id = 'turn_b1'
        model = 'gpt-5.6'
        usage = [ordered]@{
            input_tokens = 300; cached_input_tokens = 0
            output_tokens = 60; reasoning_tokens = 15
        }
    })
    $ledgerB = Join-Path $deviceB '.local\usage\codex-ledger.jsonl'
    & $codexImportPath `
        -ProjectRoot $deviceB `
        -ProjectionPath (Join-Path $captureB 'codex-turn.json') `
        -AccountReadPath (Join-Path $captureB 'codex-account-read.json') `
        -LedgerPath $ledgerB | Out-Null

    $exportedB = & $exportRunPath `
        -ProjectRoot $deviceB `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-02T00:00:00Z' |
        ConvertFrom-Json
    Assert-True (
        [string]$exportedB.status -ceq 'exported'
    ) 'A home device with export_allowed:true must be able to export a batch.'

    ### Cross-device merge + report on a third, analysis-only location ###
    $mergeRoot = Join-Path $tempRoot 'merge-analysis'
    $mergeStatePath = Join-Path $mergeRoot '.local\usage\merge\merge-state.json'
    $importedBatchPath = Join-Path $mergeRoot '.local\usage\import\device-b-batch.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $importedBatchPath) `
        -Force | Out-Null
    # Simulates the operator manually carrying an already-exported, already
    # de-identified batch from device B onto a separate analysis location.
    Copy-Item -LiteralPath ([string]$exportedB.path) -Destination $importedBatchPath
    & $mergeRunPath -ProjectRoot $mergeRoot `
        -BatchPath @($importedBatchPath) -StatePath $mergeStatePath | Out-Null
    $mergedReport = & $reportRunPath `
        -ProjectRoot $mergeRoot -Mode merged -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-02T00:00:00Z' `
        -MergeStatePath $mergeStatePath `
        -OutputPath (Join-Path $mergeRoot '.local\usage\reports\report.json') |
        ConvertFrom-Json
    Assert-True ([int]$mergedReport.rows -eq 1) (
        'Merging device B''s export into an analysis location must produce ' +
        'exactly one report row.'
    )
    $mergedReportContent = Get-Content -Raw -LiteralPath (
        Join-Path $mergeRoot '.local\usage\reports\report.json'
    ) | ConvertFrom-Json
    Assert-True (
        [string]$mergedReportContent.rows[0].alias -ceq $sharedAlias -and
        [string]$mergedReportContent.rows[0].environment -ceq 'home'
    ) 'The end-to-end chain (capture -> identity -> redact -> export -> merge -> report) must preserve alias and environment.'

    ### Session-init isolation: nothing here may touch AGENTS/CLAUDE/vault ###
    $allImplementationFiles = @(
        $rolloutPath, $codexImportPath,
        (Join-Path $core 'scripts\claude-usage-import.ps1'),
        $exportRunPath, $mergeRunPath, $reportRunPath,
        (Join-Path $core 'scripts\lib\UsageContract.psm1'),
        (Join-Path $core 'scripts\lib\UsageLedger.psm1'),
        (Join-Path $core 'scripts\lib\UsageExportGate.psm1'),
        (Join-Path $core 'scripts\lib\UsageMerge.psm1'),
        (Join-Path $core 'scripts\lib\UsageReport.psm1')
    )
    $implementationText = @(
        $allImplementationFiles | ForEach-Object {
            # Strip comments so this static scan checks executable code paths,
            # not documentation that merely explains what is NOT touched.
            (Get-Content -Raw -LiteralPath $_) `
                -replace '(?s)<#.*?#>', '' `
                -replace '(?m)#.*$', ''
        }
    ) -join "`n"
    Assert-True (
        $implementationText -notmatch (
            '(?i)AGENTS\.md|CLAUDE\.md|vault[\\/](identity|memory|governance)'
        )
    ) 'No usage-monitoring tool may touch AGENTS.md, CLAUDE.md, or vault/.'
    Assert-True (
        -not (Test-Path -LiteralPath (Join-Path $deviceA 'CLAUDE.md')) -and
        -not (Test-Path -LiteralPath (Join-Path $deviceA 'AGENTS.md'))
    ) 'Running the full pipeline must not create any session-init file.'
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?(?:codex|claude)\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'No usage-monitoring tool may launch a model or call a provider endpoint.'

    ### Disable and Remove are reversible / destructive as documented ###
    & $rolloutPath -Mode Disable -ProjectRoot $deviceB | Out-Null
    $statusBDisabled = & $rolloutPath -Mode Check -ProjectRoot $deviceB | ConvertFrom-Json
    Assert-True (
        -not [bool]$statusBDisabled.export_allowed -and
        (Test-Path -LiteralPath $ledgerB -PathType Leaf)
    ) 'Disable must turn off export without deleting existing local data.'
    Assert-Throws {
        & $rolloutPath -Mode Remove -ProjectRoot $deviceB
    } 'Remove must refuse to run without explicit confirmation.'
    & $rolloutPath -Mode Remove -ProjectRoot $deviceB -Confirm | Out-Null
    Assert-True (
        -not (Test-Path -LiteralPath $ledgerB -PathType Leaf)
    ) 'A confirmed Remove must actually delete local usage data.'

    Write-Output 'USAGE_MONITORING_ROLLOUT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
