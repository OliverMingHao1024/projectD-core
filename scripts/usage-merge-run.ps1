[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string[]]$BatchPath,
    [string]$StatePath
)

$ErrorActionPreference = 'Stop'
$usageMergePath = Join-Path $PSScriptRoot 'lib\UsageMerge.psm1'
$governanceCommonPath = Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1'
Import-Module $usageMergePath -Force -ErrorAction Stop
Import-Module $governanceCommonPath -Force -ErrorAction Stop

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot must be an existing directory.'
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $root '.local\usage\merge\merge-state.json'
}

function Resolve-UsageMergeBatchInput {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $localRoot = [IO.Path]::GetFullPath((Join-Path $Root '.local')).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolved = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $Root $Path))
    }
    $localPrefix = $localRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
        $localPrefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Batch input must stay inside ProjectRoot/.local.'
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw 'Batch input does not exist.'
    }
    if (Test-PathHasReparsePoint -Root $Root -ResolvedPath $resolved) {
        throw 'Batch input must not cross a reparse point.'
    }
    if ((Get-Item -LiteralPath $resolved -Force).Length -gt 1MB) {
        throw 'Batch input exceeds its size limit.'
    }
    return $resolved
}

$utf8 = [Text.UTF8Encoding]::new($false, $true)
$state = Read-ProjectDUsageMergeState -Path $StatePath
$results = [Collections.Generic.List[object]]::new()
$mergedAt = [DateTimeOffset]::UtcNow.ToString('o')

foreach ($path in @($BatchPath)) {
    $resolved = Resolve-UsageMergeBatchInput -Root $root -Path $path
    try {
        $json = $utf8.GetString([IO.File]::ReadAllBytes($resolved))
        $batch = $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $results.Add([pscustomobject][ordered]@{
            path = $resolved
            status = 'rejected'
            reason = 'Batch input is not valid UTF-8 JSON.'
        })
        continue
    }
    try {
        $outcome = Merge-ProjectDUsageExportBatch `
            -State $state -Batch $batch -MergedAt $mergedAt
        $state = $outcome.state
        $results.Add([pscustomobject][ordered]@{
            path = $resolved
            status = [string]$outcome.status
        })
    } catch {
        $results.Add([pscustomobject][ordered]@{
            path = $resolved
            status = 'rejected'
            reason = $_.Exception.Message
        })
    }
}

$writtenPath = Write-ProjectDUsageMergeState `
    -State $state -ProjectRoot $root -StatePath $StatePath
[pscustomobject][ordered]@{
    state_path = $writtenPath
    rows = @($state.totals).Count
    results = @($results)
} | ConvertTo-Json -Depth 12 -Compress
