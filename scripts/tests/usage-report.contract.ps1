[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runPath = Join-Path $core 'scripts\usage-report-run.ps1'
$reportModulePath = Join-Path $core 'scripts\lib\UsageReport.psm1'
$reportSchemaPath = Join-Path $core 'evals\schemas\usage-report.schema.json'
$mergeRunPath = Join-Path $core 'scripts\usage-merge-run.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "usage-report-$PID"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
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
        captured_at = '2026-08-01T00:00:00Z'
        provider = $Provider
        verification_status = 'verified'
        account_id = $AccountId
        account_alias = $Alias
        device_id = $DeviceId
        environment = 'work'
        billing_source = 'subscription'
        plan_type = [pscustomobject][ordered]@{ status = 'observed'; value = 'pro' }
    }
}

function New-UsageEventFixture {
    param(
        [Parameter(Mandatory)][string]$EventId,
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
        session_id = 'thread_1'
        turn_id = $EventId
        occurred_at = $OccurredAt
        provider = [string]$Identity.provider
        identity = $Identity
        model = [pscustomobject][ordered]@{ status = 'observed'; value = $Model }
        usage = [pscustomobject][ordered]@{
            input_tokens = [pscustomobject][ordered]@{ status = 'observed'; value = $InputTokens }
            cached_input_tokens = [pscustomobject][ordered]@{ status = 'unavailable'; value = $null }
            output_tokens = [pscustomobject][ordered]@{ status = 'observed'; value = $OutputTokens }
            reasoning_tokens = [pscustomobject][ordered]@{ status = 'unavailable'; value = $null }
            cache_creation_tokens = [pscustomobject][ordered]@{ status = 'unavailable'; value = $null }
            estimated_cost_usd = [pscustomobject][ordered]@{ status = 'unavailable'; value = $null }
        }
    }
}

function Test-UsageReportSameInstant {
    <#
    ConvertFrom-Json auto-detects ISO 8601 strings and returns culture-aware
    [DateTime] values rather than strings, so string-pattern matches
    against a parsed period.start/end are unreliable. Compare as
    DateTimeOffset instants instead.
    #>
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$ExpectedIso
    )
    return ([DateTimeOffset]$Value) -eq ([DateTimeOffset]$ExpectedIso)
}

function Write-LedgerFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][array]$Events
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $lines = @($Events | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress })
    Set-Content -LiteralPath $Path -Value ($lines -join "`n") `
        -Encoding utf8 -NoNewline
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Assert-True (
        Test-Path -LiteralPath $runPath -PathType Leaf
    ) 'The usage report run entrypoint must exist.'
    Assert-True (
        Test-Path -LiteralPath $reportModulePath -PathType Leaf
    ) 'The usage report module must exist.'
    Assert-True (
        Test-Path -LiteralPath $reportSchemaPath -PathType Leaf
    ) 'The usage report schema must exist.'

    # --- local mode: two events on two different days must become two rows ---
    $projectA = Join-Path $tempRoot 'proj-a'
    $identityA = New-VerifiedIdentityFixture
    $ledgerA = Join-Path $projectA '.local\usage\codex-ledger.jsonl'
    Write-LedgerFixture -Path $ledgerA -Events @(
        (New-UsageEventFixture -EventId 'evt1' `
            -OccurredAt '2026-08-01T10:00:00Z' -Identity $identityA `
            -InputTokens 100 -OutputTokens 20),
        (New-UsageEventFixture -EventId 'evt2' `
            -OccurredAt '2026-08-01T14:00:00Z' -Identity $identityA `
            -InputTokens 50 -OutputTokens 10),
        (New-UsageEventFixture -EventId 'evt3' `
            -OccurredAt '2026-08-03T09:00:00Z' -Identity $identityA `
            -InputTokens 9999 -OutputTokens 5000)
    )

    $diagnosticsPath = Join-Path $projectA (
        '.local\usage\diagnostics\identity-events.jsonl'
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $diagnosticsPath) `
        -Force | Out-Null
    $diagLines = @(
        ([pscustomobject][ordered]@{
            schema_version = 1
            occurred_at = '2026-08-01T11:00:00Z'
            provider = 'codex'
            verification_status = 'unknown'
            device_id = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            environment = 'work'
        } | ConvertTo-Json -Depth 8 -Compress),
        ([pscustomobject][ordered]@{
            schema_version = 1
            occurred_at = '2026-08-01T12:00:00Z'
            provider = 'codex'
            verification_status = 'mismatch'
            device_id = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            environment = 'work'
        } | ConvertTo-Json -Depth 8 -Compress)
    )
    Set-Content -LiteralPath $diagnosticsPath -Value ($diagLines -join "`n") `
        -Encoding utf8 -NoNewline

    $outputPathA = Join-Path $projectA '.local\usage\reports\report.json'
    $resultA = & $runPath `
        -ProjectRoot $projectA -Mode local -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-04T00:00:00Z' `
        -BaselineInputTokensPerRun 1000 `
        -OutputPath $outputPathA | ConvertFrom-Json
    Assert-True (
        [int]$resultA.rows -eq 2
    ) 'Events on two different days must become two report rows.'

    $reportJson = Get-Content -Raw -LiteralPath $outputPathA
    Assert-True (
        Test-Json -Json $reportJson -SchemaFile $reportSchemaPath -ErrorAction Stop
    ) 'The report must conform to its canonical schema.'
    $report = $reportJson | ConvertFrom-Json
    $day1Row = @(
        $report.rows | Where-Object {
            Test-UsageReportSameInstant $_.period.start '2026-08-01T00:00:00Z'
        }
    )[0]
    Assert-True (
        [long]$day1Row.input_tokens.value -eq 150 -and
        [int]$day1Row.run_count -eq 2 -and
        [string]$day1Row.alias -ceq 'personal-codex' -and
        [string]$day1Row.device_id -ceq 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    ) 'Same-day events must aggregate by alias/provider/device/model.'

    # --- identity warnings ---
    $unknownWarning = @(
        $report.warnings | Where-Object type -ceq 'unknown_identity'
    )
    $mismatchWarning = @(
        $report.warnings | Where-Object type -ceq 'account_mismatch'
    )
    Assert-True (
        $unknownWarning.Count -eq 1 -and [int]$unknownWarning[0].count -eq 1 -and
        $mismatchWarning.Count -eq 1 -and [int]$mismatchWarning[0].count -eq 1
    ) 'Unknown and mismatched identity diagnostics must each surface a warning.'

    # --- data gap: 2026-08-02 has no events ---
    $gapWarnings = @($report.warnings | Where-Object type -ceq 'data_gap')
    Assert-True (
        $gapWarnings.Count -eq 1 -and
        (Test-UsageReportSameInstant $gapWarnings[0].period.start '2026-08-02T00:00:00Z')
    ) 'A day with zero rows inside the requested period must be flagged as a data gap.'

    # --- anomalous usage: day 3 far exceeds the baseline ---
    $anomalyWarnings = @($report.warnings | Where-Object type -ceq 'anomalous_usage')
    Assert-True (
        $anomalyWarnings.Count -eq 1 -and
        [string]$anomalyWarnings[0].metric -ceq 'input_tokens' -and
        (Test-UsageReportSameInstant $anomalyWarnings[0].period.start '2026-08-03T00:00:00Z')
    ) 'Usage far above the supplied baseline must be flagged as anomalous.'

    # --- no baseline supplied: no anomaly warnings at all ---
    $outputPathA2 = Join-Path $projectA '.local\usage\reports\report-no-baseline.json'
    & $runPath `
        -ProjectRoot $projectA -Mode local -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-04T00:00:00Z' `
        -OutputPath $outputPathA2 | Out-Null
    $reportNoBaseline = Get-Content -Raw -LiteralPath $outputPathA2 | ConvertFrom-Json
    Assert-True (
        @($reportNoBaseline.warnings | Where-Object type -ceq 'anomalous_usage').Count -eq 0
    ) 'Without a supplied baseline, no anomaly warnings may be produced.'

    # --- quota snapshot stays a separate section, never mixed into rows ---
    $quotaPath = Join-Path $projectA '.local\usage\codex-quota-snapshot.json'
    Write-JsonFixture -Path $quotaPath -Value ([ordered]@{
        schema_version = 1
        captured_at = '2026-08-01T00:00:00Z'
        provider = 'codex'
        identity = [ordered]@{
            verification_status = 'verified'
            account_id = 'acct_11111111111111111111111111111111'
            account_alias = 'personal-codex'
            device_id = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            environment = 'work'
            billing_source = 'subscription'
        }
        windows = @([ordered]@{
            limit_id = 'codex'; window = 'primary'; used_percent = 30
            window_duration_minutes = 300; resets_at = 1787882400
        })
    })
    $outputPathA3 = Join-Path $projectA '.local\usage\reports\report-with-quota.json'
    & $runPath `
        -ProjectRoot $projectA -Mode local -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-04T00:00:00Z' `
        -QuotaSnapshotPath @($quotaPath) `
        -OutputPath $outputPathA3 | Out-Null
    $reportWithQuota = Get-Content -Raw -LiteralPath $outputPathA3 | ConvertFrom-Json
    Assert-True (
        @($reportWithQuota.quota_snapshots).Count -eq 1 -and
        [string]$reportWithQuota.quota_snapshots[0].windows[0].used_percent -eq '30'
    ) 'Official quota snapshots must appear in their own report section.'
    Assert-True (
        (
            $reportWithQuota.rows |
                Where-Object { $_.PSObject.Properties.Name -contains 'used_percent' }
        ).Count -eq 0
    ) 'Quota fields must never be mixed into usage rows.'

    # --- determinism: same inputs, same rows/warnings (excluding generated_at) ---
    $outputPathA4 = Join-Path $projectA '.local\usage\reports\report-repeat.json'
    & $runPath `
        -ProjectRoot $projectA -Mode local -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-04T00:00:00Z' `
        -BaselineInputTokensPerRun 1000 `
        -OutputPath $outputPathA4 | Out-Null
    $reportRepeat = Get-Content -Raw -LiteralPath $outputPathA4 | ConvertFrom-Json
    Assert-True (
        ($report.rows | ConvertTo-Json -Depth 20 -Compress) -ceq (
            $reportRepeat.rows | ConvertTo-Json -Depth 20 -Compress
        ) -and
        ($report.warnings | ConvertTo-Json -Depth 20 -Compress) -ceq (
            $reportRepeat.warnings | ConvertTo-Json -Depth 20 -Compress
        )
    ) 'The same inputs must produce byte-identical rows and warnings.'

    # --- content safety ---
    Assert-True (
        $reportJson -notmatch (
            '(?i)acct_1111|thread_1|@example|C:\\\\|/home/|github\.com'
        )
    ) 'The report must exclude account_id, session identifiers, email, and paths.'

    # --- merged mode ---
    $batchPath = Join-Path $projectA '.local\usage\import\batch.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $batchPath) -Force |
        Out-Null
    Write-JsonFixture -Path $batchPath -Value ([ordered]@{
        schema_version = 1
        policy_version = 'home-desktop-v1'
        redaction_version = 'v1'
        source_version = 'test-v1'
        generated_at = '2026-08-01T23:00:00Z'
        period = [ordered]@{
            start = '2026-08-01T00:00:00Z'
            end = '2026-08-02T00:00:00Z'
        }
        rows = @([ordered]@{
            alias = 'personal-codex'
            provider = 'codex'
            model = 'gpt-5.6'
            device_id = 'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            environment = 'home'
            run_count = 3
            input_tokens = [ordered]@{ status = 'observed'; value = 300 }
            cached_input_tokens = [ordered]@{ status = 'unavailable'; value = $null }
            output_tokens = [ordered]@{ status = 'observed'; value = 60 }
            reasoning_tokens = [ordered]@{ status = 'unavailable'; value = $null }
            cache_creation_tokens = [ordered]@{ status = 'unavailable'; value = $null }
            estimated_cost_usd = [ordered]@{ status = 'unavailable'; value = $null }
        })
    })
    $mergeStatePath = Join-Path $projectA '.local\usage\merge\merge-state.json'
    & $mergeRunPath -ProjectRoot $projectA -BatchPath @($batchPath) `
        -StatePath $mergeStatePath | Out-Null
    $outputPathMerged = Join-Path $projectA '.local\usage\reports\report-merged.json'
    $resultMerged = & $runPath `
        -ProjectRoot $projectA -Mode merged -GroupBy day `
        -PeriodStart '2026-08-01T00:00:00Z' -PeriodEnd '2026-08-02T00:00:00Z' `
        -MergeStatePath $mergeStatePath `
        -OutputPath $outputPathMerged | ConvertFrom-Json
    Assert-True (
        [int]$resultMerged.rows -eq 1
    ) 'Merged mode must produce a row from the merge-state totals.'
    $reportMerged = Get-Content -Raw -LiteralPath $outputPathMerged | ConvertFrom-Json
    Assert-True (
        Test-Json -Json (Get-Content -Raw -LiteralPath $outputPathMerged) `
            -SchemaFile $reportSchemaPath -ErrorAction Stop
    ) 'The merged-mode report must also conform to its canonical schema.'
    Assert-True (
        [string]$reportMerged.rows[0].environment -ceq 'home' -and
        [string]$reportMerged.rows[0].device_id -ceq (
            'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        ) -and
        [long]$reportMerged.rows[0].input_tokens.value -eq 300
    ) 'Merged-mode rows must retain device_id/environment from the merge state.'

    # --- no model or network calls; deterministic implementation ---
    $implementationText = @(
        Get-Content -Raw -LiteralPath $runPath
        Get-Content -Raw -LiteralPath $reportModulePath
    ) -join "`n"
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?(?:codex|claude)\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'Usage reporting must not launch a model or call a provider endpoint.'
    Assert-True (
        (Get-Content -Raw -LiteralPath $runPath) -notmatch '(?i)Get-Random'
    ) 'Reporting must not depend on non-deterministic values.'

    Write-Output 'USAGE_REPORT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
