[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$check = Join-Path $core 'scripts\projectd-check.ps1'
$tempFleet = Join-Path ([IO.Path]::GetTempPath()) "projectd-check-$PID.json"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    $json = (& $check -ProjectRoot $core -SkipGlobal -SkipWiring -Json | ConvertFrom-Json)
    Assert-True $json.passed 'Healthy workspace must pass.'
    Assert-True (@($json.checks).Count -ge 4) 'JSON output must include all checks.'

    Set-Content -LiteralPath $tempFleet -Value '[{"path":"D:\\missing-project","category":"side","packs":["python"]}]' -Encoding utf8 -NoNewline
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $check,
        '-ProjectRoot', $core, '-FleetPath', $tempFleet, '-SkipGlobal'
    ) -Wait -PassThru -WindowStyle Hidden
    Assert-True ($process.ExitCode -ne 0) 'Invalid fleet must return a non-zero exit code.'
    Write-Output 'PROJECTD_CHECK_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempFleet) { Remove-Item -LiteralPath $tempFleet -Force }
}
