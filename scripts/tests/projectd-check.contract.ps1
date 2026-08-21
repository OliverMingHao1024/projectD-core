[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$check = Join-Path $core 'scripts\projectd-check.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "projectd-check-$PID"
$tempFleet = Join-Path $tempRoot 'fleet.json'
$tempProject = Join-Path $tempRoot 'project'
$stdoutPath = Join-Path $tempRoot 'stdout.json'
$stderrPath = Join-Path $tempRoot 'stderr.txt'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    New-Item -ItemType Directory -Path $tempProject -Force | Out-Null
    $validFleet = @(
        [pscustomobject]@{
            path = $tempProject
            category = 'side'
            packs = @('python')
        }
    ) | ConvertTo-Json -Depth 3
    Set-Content `
        -LiteralPath $tempFleet `
        -Value $validFleet `
        -Encoding utf8 `
        -NoNewline

    $json = (
        & $check `
            -ProjectRoot $core `
            -FleetPath $tempFleet `
            -SkipGlobal `
            -SkipWiring `
            -Json |
            ConvertFrom-Json
    )
    Assert-True $json.passed 'Healthy workspace must pass.'
    Assert-True (@($json.checks).Count -ge 5) 'JSON output must include all checks.'
    Assert-True (
        @($json.checks | Where-Object name -EQ 'skill-registry').Count -eq 1
    ) 'Unified check must validate the Skill registry.'
    Assert-True (
        @($json.checks |
            Where-Object name -EQ 'fleet-inspect-contract').Count -eq 1
    ) 'Unified check must validate the bounded Fleet inspector.'
    $checkContent = Get-Content -Raw -LiteralPath $check
    Assert-True (
        $checkContent.Contains('[switch]$SkipFleet')
    ) 'Unified check must support repository-local execution.'
    Assert-True (
        -not $checkContent.Contains('Get-ChildItem $core -Recurse')
    ) 'Project checks must not recursively enumerate the repository root.'
    foreach ($allowedRoot in @('core', 'packs', 'scripts', 'vault', 'docs')) {
        Assert-True (
            $checkContent.Contains("'$allowedRoot'")
        ) "Text scan allowlist must include $allowedRoot."
    }
    foreach ($excludedDirectory in @(
        '.git',
        '.local',
        'node_modules',
        '_staging',
        '__pycache__',
        '.venv'
    )) {
        Assert-True (
            $checkContent.Contains("'$excludedDirectory'")
        ) "Text scan must prune $excludedDirectory before recursion."
    }
    Assert-True (
        $checkContent.Contains('[IO.FileAttributes]::ReparsePoint')
    ) 'Text scan must not follow junctions or symbolic links.'

    $governanceJson = (
        & $check `
            -ProjectRoot $core `
            -FleetPath $tempFleet `
            -SkipGlobal `
            -SkipWiring `
            -GovernanceEvals `
            -Json |
            ConvertFrom-Json
    )
    Assert-True $governanceJson.passed 'All governance eval layers must pass.'
    foreach ($name in @(
        'governance-structural-evals',
        'governance-behavior-catalog',
        'governance-asset-inventory',
        'governance-security-traces',
        'governance-host-trial-contract',
        'governance-host-upgrade-gate-contract',
        'governance-host-run-plan-contract'
    )) {
        Assert-True (
            @($governanceJson.checks | Where-Object name -CEQ $name).Count -eq 1
        ) "Unified check must report $name separately."
    }

    Set-Content `
        -LiteralPath $tempFleet `
        -Value '[{"path":"D:\\missing-project","category":"side","packs":["python"]}]' `
        -Encoding utf8 `
        -NoNewline
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $check,
        '-ProjectRoot', $core, '-FleetPath', $tempFleet, '-SkipGlobal'
    ) -Wait -PassThru -WindowStyle Hidden
    Assert-True ($process.ExitCode -ne 0) 'Invalid fleet must return a non-zero exit code.'

    Set-Content `
        -LiteralPath $tempFleet `
        -Value $validFleet `
        -Encoding utf8 `
        -NoNewline
    $childProcess = Start-Process `
        -FilePath 'pwsh.exe' `
        -ArgumentList @(
            '-NoProfile', '-File', $check,
            '-ProjectRoot', $core,
            '-FleetPath', $tempFleet,
            '-SkipGlobal',
            '-Json'
        ) `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Wait `
        -PassThru `
        -WindowStyle Hidden
    $childJson = Get-Content -Raw -LiteralPath $stdoutPath | ConvertFrom-Json
    $fleetWiring = @(
        $childJson.checks | Where-Object name -EQ 'fleet-wiring'
    )
    Assert-True (
        $childProcess.ExitCode -ne 0
    ) 'A failed child wiring check must return a non-zero exit code.'
    Assert-True (
        $fleetWiring.Count -eq 1 -and -not $fleetWiring[0].passed
    ) 'A failed child wiring check must be reported as failed.'
    Write-Output 'PROJECTD_CHECK_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
