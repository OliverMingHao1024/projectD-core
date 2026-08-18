[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaselinePath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $root 'evals\governance-baseline.json'
}

$results = @()
try {
    $baseline = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    if ($baseline.schema_version -ne 1) {
        throw "Unsupported schema_version: $($baseline.schema_version)"
    }
    $cases = @($baseline.cases)
    if ($cases.Count -eq 0) {
        throw 'Baseline must contain at least one case.'
    }

    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($case in $cases) {
        $id = [string]$case.id
        $relativePath = [string]$case.file
        if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) {
            throw "Case ids must be non-empty and unique: $id"
        }
        if (
            [IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -split '[\\/]' -contains '..'
        ) {
            throw "$id uses an unsafe file path: $relativePath"
        }
        $path = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$id resolves outside ProjectRoot: $relativePath"
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $results += [pscustomobject]@{
                id = $id; passed = $false; message = "Missing file: $relativePath"
            }
            continue
        }

        $content = Get-Content -Raw -LiteralPath $path
        $missing = @(
            @($case.must_contain) |
                Where-Object { -not [string]::IsNullOrEmpty([string]$_) } |
                Where-Object { -not $content.Contains([string]$_) }
        )
        $forbidden = @(
            @($case.must_not_contain) |
                Where-Object { -not [string]::IsNullOrEmpty([string]$_) } |
                Where-Object { $content.Contains([string]$_) }
        )
        $details = @()
        if ($missing.Count) { $details += "missing: $($missing -join ' | ')" }
        if ($forbidden.Count) { $details += "forbidden: $($forbidden -join ' | ')" }
        $results += [pscustomobject]@{
            id = $id
            passed = ($details.Count -eq 0)
            message = if ($details.Count) { $details -join '; ' } else { 'Baseline matched' }
        }
    }
} catch {
    $results = @([pscustomobject]@{
        id = 'baseline'; passed = $false; message = $_.Exception.Message
    })
}

$failed = @($results | Where-Object { -not $_.passed })
if ($Json) {
    [pscustomobject]@{
        passed = ($failed.Count -eq 0)
        evaluated = $results.Count
        checks = $results
    } | ConvertTo-Json -Depth 4
} else {
    foreach ($result in $results) {
        $state = if ($result.passed) { 'PASS' } else { 'FAIL' }
        "[$state] $($result.id): $($result.message)"
    }
    "Summary: $(@($results | Where-Object passed).Count) passed, $($failed.Count) failed."
}
if ($failed.Count) { exit 1 }
