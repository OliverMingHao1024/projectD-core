[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$eval = Join-Path $core 'scripts\governance-eval.ps1'
$baseline = Join-Path $core 'evals\governance-baseline.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "governance-eval-$PID"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    $healthy = & $eval -ProjectRoot $core -BaselinePath $baseline -Json |
        ConvertFrom-Json
    Assert-True $healthy.passed 'The canonical governance baseline must pass.'
    Assert-True ($healthy.evaluated -ge 10) 'The baseline must stay representative.'

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot 'fixture.md') -Value 'changed'
    $brokenBaseline = [pscustomobject]@{
        schema_version = 1
        cases = @([pscustomobject]@{
            id = 'detect-regression'
            file = 'fixture.md'
            must_contain = @('expected governance behavior')
        })
    }
    $brokenPath = Join-Path $tempRoot 'baseline.json'
    $brokenBaseline | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $brokenPath -Encoding utf8

    $outputPath = Join-Path $tempRoot 'result.json'
    $process = Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
        '-NoProfile', '-File', $eval,
        '-ProjectRoot', $tempRoot,
        '-BaselinePath', $brokenPath,
        '-Json'
    ) -RedirectStandardOutput $outputPath -Wait -PassThru -WindowStyle Hidden
    $broken = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
    Assert-True ($process.ExitCode -ne 0) 'A baseline regression must fail.'
    Assert-True (-not $broken.passed) 'JSON must report a failed regression.'
    Write-Output 'GOVERNANCE_EVAL_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
