[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script = Join-Path $core 'scripts\fleet-inspect.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "fleet-inspect-$PID"
$projectPath = Join-Path $tempRoot 'project'
$fleetPath = Join-Path $tempRoot 'fleet.json'
$invalidFleetPath = Join-Path $tempRoot 'invalid-fleet.json'
$stdoutPath = Join-Path $tempRoot 'stdout.json'
$stderrPath = Join-Path $tempRoot 'stderr.txt'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

try {
    New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
    $agentsPath = Join-Path $projectPath 'AGENTS.md'
    Set-Content `
        -LiteralPath $agentsPath `
        -Value 'project-owned content' `
        -Encoding utf8 `
        -NoNewline

    @(
        [pscustomobject]@{
            path = $projectPath
            category = 'side'
            packs = @('python')
        }
    ) |
        ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath $fleetPath -Encoding utf8 -NoNewline

    $result = & $script -FleetPath $fleetPath -Json | ConvertFrom-Json
    Assert-True $result.passed 'A valid explicit Fleet must pass inspection.'
    Assert-True (
        $result.scan_scope -eq 'fleet-config-only'
    ) 'Inspection must declare its bounded scan scope.'
    Assert-True (
        -not $result.source_content_scanned
    ) 'Inspection must not scan project source content.'
    Assert-True (
        @($result.projects).Count -eq 1
    ) 'Inspection must return exactly the configured projects.'
    Assert-True (
        @($result.projects[0].entry_targets).Count -eq 3
    ) 'Inspection may target only the three governance entry files.'
    Assert-True (
        (Get-Content -Raw -LiteralPath $agentsPath) -eq
            'project-owned content'
    ) 'Inspection must not modify an existing entry file.'
    Assert-True (
        -not (Test-Path -LiteralPath (Join-Path $projectPath 'CLAUDE.md'))
    ) 'Inspection must not create missing entry files.'

    $scriptContent = Get-Content -Raw -LiteralPath $script
    foreach ($forbidden in @(
        'Get-ChildItem',
        '-Recurse',
        'FromBase64String',
        'Invoke-Expression',
        'Invoke-WebRequest',
        'Invoke-RestMethod'
    )) {
        Assert-True (
            -not $scriptContent.Contains($forbidden)
        ) "Fleet inspector must not contain $forbidden."
    }

    @(
        [pscustomobject]@{
            path = (Join-Path $tempRoot 'missing-project')
            category = 'side'
            packs = @('python')
        }
    ) |
        ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath $invalidFleetPath -Encoding utf8 -NoNewline

    $process = Start-Process `
        -FilePath 'pwsh.exe' `
        -ArgumentList @(
            '-NoProfile',
            '-File',
            $script,
            '-FleetPath',
            $invalidFleetPath,
            '-Json'
        ) `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Wait `
        -PassThru `
        -WindowStyle Hidden
    $invalidResult = Get-Content -Raw -LiteralPath $stdoutPath |
        ConvertFrom-Json
    Assert-True (
        $process.ExitCode -ne 0
    ) 'A Fleet containing a missing project must fail inspection.'
    Assert-True (
        @($invalidResult.issues |
            Where-Object code -EQ 'project-directory-missing').Count -eq 1
    ) 'A missing project must produce a structured issue.'

    Write-Output 'FLEET_INSPECT_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
