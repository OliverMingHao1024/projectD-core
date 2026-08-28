[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$PeriodStart,
    [Parameter(Mandatory)][string]$PeriodEnd,
    [string[]]$LedgerPath,
    [string]$PolicyPath,
    [string]$OutputPath,
    [string]$SourceVersion = 'projectd-core-usage-export-v1'
)

$ErrorActionPreference = 'Stop'
$usageLedgerPath = Join-Path $PSScriptRoot 'lib\UsageLedger.psm1'
$usageExportGatePath = Join-Path $PSScriptRoot 'lib\UsageExportGate.psm1'
$governanceCommonPath = Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1'
Import-Module $usageLedgerPath -Force -ErrorAction Stop
Import-Module $usageExportGatePath -Force -ErrorAction Stop
Import-Module $governanceCommonPath -Force -ErrorAction Stop

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot must be an existing directory.'
}
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $root '.local\governance\usage-export-policy.json'
}
if (-not $LedgerPath -or $LedgerPath.Count -eq 0) {
    $LedgerPath = @(
        (Join-Path $root '.local\usage\codex-ledger.jsonl'),
        (Join-Path $root '.local\usage\claude-ledger.jsonl')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}
$generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $safeStamp = $generatedAt -replace '[^0-9A-Za-z]', '-'
    $OutputPath = Join-Path $root (
        ".local\usage\export\usage-export-$safeStamp.json"
    )
}

$periodStartUtc = ([DateTimeOffset]$PeriodStart).ToUniversalTime()
$periodEndUtc = ([DateTimeOffset]$PeriodEnd).ToUniversalTime()
if ($periodEndUtc -le $periodStartUtc) {
    throw 'PeriodEnd must be after PeriodStart.'
}

$policy = Read-ProjectDUsageExportPolicy -Path $PolicyPath

try {
    $allRecords = [Collections.Generic.List[object]]::new()
    foreach ($ledger in @($LedgerPath | Where-Object { $_ })) {
        foreach ($record in @(Read-ProjectDUsageLedgerEvents -Path $ledger)) {
            $occurred = [DateTimeOffset]$record.event.occurred_at
            if ($occurred -ge $periodStartUtc -and $occurred -lt $periodEndUtc) {
                $allRecords.Add($record)
            }
        }
    }

    $batch = ConvertTo-ProjectDUsageExportBatch `
        -Records @($allRecords) `
        -Policy $policy `
        -PeriodStart $periodStartUtc.ToString('o') `
        -PeriodEnd $periodEndUtc.ToString('o') `
        -SourceVersion $SourceVersion `
        -GeneratedAt $generatedAt

    $localRoot = [IO.Path]::GetFullPath((Join-Path $root '.local'))
    $resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) {
        [IO.Path]::GetFullPath($OutputPath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $OutputPath))
    }
    if (-not $resolvedOutput.StartsWith(
        $localRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'OutputPath must stay inside ProjectRoot/.local.'
    }
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $resolvedOutput
    ) -Force | Out-Null
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $resolvedOutput) {
        throw 'OutputPath must not cross a reparse point.'
    }
    $batch | ConvertTo-Json -Depth 32 | Set-Content `
        -LiteralPath $resolvedOutput -Encoding utf8 -NoNewline
    [pscustomobject][ordered]@{
        status = 'exported'
        rows = @($batch.rows).Count
        path = $resolvedOutput
    } | ConvertTo-Json -Compress
} catch {
    $quarantinePath = Write-ProjectDUsageExportQuarantine `
        -ProjectRoot $root -Reason $_.Exception.Message
    [pscustomobject][ordered]@{
        status = 'quarantined'
        reason = $_.Exception.Message
        quarantine_path = $quarantinePath
    } | ConvertTo-Json -Compress
    throw
}
