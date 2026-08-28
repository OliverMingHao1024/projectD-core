[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][ValidateSet('local', 'merged')][string]$Mode,
    [ValidateSet('day', 'week')][string]$GroupBy = 'day',
    [Parameter(Mandatory)][string]$PeriodStart,
    [Parameter(Mandatory)][string]$PeriodEnd,
    [string[]]$LedgerPath,
    [string]$MergeStatePath,
    [string]$IdentityDiagnosticsPath,
    [string[]]$QuotaSnapshotPath,
    [double]$BaselineInputTokensPerRun,
    [double]$BaselineOutputTokensPerRun,
    [double]$BaselineCostPerRun,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\UsageLedger.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\UsageMerge.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\UsageReport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot must be an existing directory.'
}
$localRoot = [IO.Path]::GetFullPath((Join-Path $root '.local'))

function Resolve-BoundedLocalPath {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $Path))
    }
    if (-not $resolved.StartsWith(
        $localRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Path must stay inside ProjectRoot/.local.'
    }
    return $resolved
}

$generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
$periodStartUtc = ([DateTimeOffset]$PeriodStart).ToUniversalTime()
$periodEndUtc = ([DateTimeOffset]$PeriodEnd).ToUniversalTime()
if ($periodEndUtc -le $periodStartUtc) {
    throw 'PeriodEnd must be after PeriodStart.'
}

$baseline = @{}
if ($PSBoundParameters.ContainsKey('BaselineInputTokensPerRun')) {
    $baseline['input_tokens'] = $BaselineInputTokensPerRun
}
if ($PSBoundParameters.ContainsKey('BaselineOutputTokensPerRun')) {
    $baseline['output_tokens'] = $BaselineOutputTokensPerRun
}
if ($PSBoundParameters.ContainsKey('BaselineCostPerRun')) {
    $baseline['estimated_cost_usd'] = $BaselineCostPerRun
}

$rows = @()
$identityWarnings = @()

if ($Mode -ceq 'local') {
    if (-not $LedgerPath -or $LedgerPath.Count -eq 0) {
        $LedgerPath = @(
            (Join-Path $root '.local\usage\codex-ledger.jsonl'),
            (Join-Path $root '.local\usage\claude-ledger.jsonl')
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    }
    $records = [Collections.Generic.List[object]]::new()
    foreach ($ledger in @($LedgerPath | Where-Object { $_ })) {
        $resolvedLedger = Resolve-BoundedLocalPath -Path $ledger
        foreach ($record in @(Read-ProjectDUsageLedgerEvents -Path $resolvedLedger)) {
            $occurred = [DateTimeOffset]$record.event.occurred_at
            if ($occurred -ge $periodStartUtc -and $occurred -lt $periodEndUtc) {
                $records.Add($record)
            }
        }
    }
    $rows = New-ProjectDUsageReportRowsFromLedger `
        -Records @($records) -GroupBy $GroupBy

    if ([string]::IsNullOrWhiteSpace($IdentityDiagnosticsPath)) {
        $IdentityDiagnosticsPath = Join-Path $root (
            '.local\usage\diagnostics\identity-events.jsonl'
        )
    } else {
        $IdentityDiagnosticsPath = Resolve-BoundedLocalPath -Path $IdentityDiagnosticsPath
    }
    $diagnostics = [Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $IdentityDiagnosticsPath -PathType Leaf) {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $text = $utf8.GetString([IO.File]::ReadAllBytes($IdentityDiagnosticsPath))
        foreach ($line in @((($text -replace "`r", '') -split "`n"))) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            $occurred = [DateTimeOffset]$record.occurred_at
            if ($occurred -ge $periodStartUtc -and $occurred -lt $periodEndUtc) {
                $diagnostics.Add($record)
            }
        }
    }
    $identityWarnings = Get-ProjectDUsageIdentityWarnings `
        -Diagnostics @($diagnostics) -GroupBy $GroupBy
} else {
    if ([string]::IsNullOrWhiteSpace($MergeStatePath)) {
        $MergeStatePath = Join-Path $root '.local\usage\merge\merge-state.json'
    } else {
        $MergeStatePath = Resolve-BoundedLocalPath -Path $MergeStatePath
    }
    $state = Read-ProjectDUsageMergeState -Path $MergeStatePath
    $allRows = New-ProjectDUsageReportRowsFromMergeState -State $state
    $rows = @(
        $allRows | Where-Object {
            $rowStart = [DateTimeOffset]$_.period.start
            $rowStart -ge $periodStartUtc -and $rowStart -lt $periodEndUtc
        }
    )
}

$quotaSnapshots = [Collections.Generic.List[object]]::new()
if (-not $QuotaSnapshotPath -or $QuotaSnapshotPath.Count -eq 0) {
    $QuotaSnapshotPath = @(
        Join-Path $root '.local\usage\codex-quota-snapshot.json'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}
foreach ($path in @($QuotaSnapshotPath | Where-Object { $_ })) {
    $resolvedQuota = Resolve-BoundedLocalPath -Path $path
    if (Test-Path -LiteralPath $resolvedQuota -PathType Leaf) {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $quotaSnapshots.Add(
            ($utf8.GetString([IO.File]::ReadAllBytes($resolvedQuota)) |
                ConvertFrom-Json -ErrorAction Stop)
        )
    }
}

$dataGapWarnings = Get-ProjectDUsageDataGapWarnings `
    -Rows @($rows) `
    -PeriodStart $periodStartUtc.ToString('o') `
    -PeriodEnd $periodEndUtc.ToString('o') `
    -GroupBy $GroupBy
$anomalyWarnings = Get-ProjectDUsageAnomalyWarnings `
    -Rows @($rows) -BaselinePerRun $baseline
$warnings = @($identityWarnings) + @($dataGapWarnings) + @($anomalyWarnings)

$report = New-ProjectDUsageReport `
    -Mode $Mode -GroupBy $GroupBy `
    -Rows @($rows) -Warnings @($warnings) `
    -QuotaSnapshots @($quotaSnapshots) `
    -PeriodStart $periodStartUtc.ToString('o') `
    -PeriodEnd $periodEndUtc.ToString('o') `
    -GeneratedAt $generatedAt

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $safeStamp = $generatedAt -replace '[^0-9A-Za-z]', '-'
    $OutputPath = Join-Path $root (
        ".local\usage\reports\usage-report-$safeStamp.json"
    )
}
$resolvedOutput = Resolve-BoundedLocalPath -Path $OutputPath
New-Item -ItemType Directory -Path (
    Split-Path -Parent $resolvedOutput
) -Force | Out-Null
if (Test-PathHasReparsePoint -Root $root -ResolvedPath $resolvedOutput) {
    throw 'OutputPath must not cross a reparse point.'
}
$report | ConvertTo-Json -Depth 32 | Set-Content `
    -LiteralPath $resolvedOutput -Encoding utf8 -NoNewline
[pscustomobject][ordered]@{
    path = $resolvedOutput
    rows = @($report.rows).Count
    warnings = @($report.warnings).Count
} | ConvertTo-Json -Compress
