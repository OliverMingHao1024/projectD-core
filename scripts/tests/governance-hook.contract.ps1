[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $core 'scripts\ProjectD.GovernanceHook.psm1'
$managerPath = Join-Path $core 'scripts\governance-hooks.ps1'
$adapterPath = Join-Path $core 'scripts\hooks\pre-push'
$checkPath = Join-Path $core 'scripts\projectd-check.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "governance-hook-$PID"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    Assert-True (Test-Path -LiteralPath $modulePath -PathType Leaf) (
        'Governance hook module must exist.'
    )
    Assert-True (Test-Path -LiteralPath $managerPath -PathType Leaf) (
        'Governance hook manager must exist.'
    )
    Assert-True (Test-Path -LiteralPath $adapterPath -PathType Leaf) (
        'Tracked pre-push adapter must exist.'
    )

    Import-Module $modulePath -Force
    $pass = Invoke-ProjectDGovernanceHook `
        -Event PrePush `
        -ProjectRoot $core `
        -CheckArguments @('-SkipFleet', '-SkipGlobal', '-SkipWiring')
    Assert-True ($pass.decision -eq 'allow') (
        'Healthy repository-local checks must allow pre-push.'
    )
    Assert-True ($pass.event -eq 'pre-push') (
        'Hook result must identify its normalized event.'
    )
    Assert-True (-not [string]::IsNullOrWhiteSpace($pass.message)) (
        'Hook result must include a user-facing message.'
    )

    $unsupported = Invoke-ProjectDGovernanceHook `
        -Event SessionStart `
        -ProjectRoot $core
    Assert-True ($unsupported.decision -eq 'warn') (
        'Unsupported advisory events must warn without blocking.'
    )

    $unapprovedRoot = Join-Path $tempRoot 'unapproved-root'
    New-Item -ItemType Directory -Path $unapprovedRoot -Force | Out-Null
    $blocked = Invoke-ProjectDGovernanceHook `
        -Event PrePush `
        -ProjectRoot $unapprovedRoot
    Assert-True ($blocked.decision -eq 'block') (
        'A root outside the projectD-core repository shape must be blocked.'
    )

    $timeoutRoot = Join-Path $tempRoot 'timeout-root'
    New-Item `
        -ItemType Directory `
        -Path (Join-Path $timeoutRoot 'core\constitution') `
        -Force |
        Out-Null
    New-Item `
        -ItemType Directory `
        -Path (Join-Path $timeoutRoot 'scripts') `
        -Force |
        Out-Null
    Set-Content `
        -LiteralPath (Join-Path $timeoutRoot 'core\constitution\rules.md') `
        -Value '# fixture' `
        -Encoding utf8
    Set-Content `
        -LiteralPath (Join-Path $timeoutRoot 'scripts\projectd-check.ps1') `
        -Value 'Start-Sleep -Seconds 10' `
        -Encoding utf8
    $timedOut = Invoke-ProjectDGovernanceHook `
        -Event PrePush `
        -ProjectRoot $timeoutRoot `
        -CheckArguments @() `
        -TimeoutSeconds 1
    Assert-True ($timedOut.decision -eq 'block') (
        'A timed-out governance check must block pre-push.'
    )
    Assert-True ($timedOut.message.Contains('timeout')) (
        'A timeout result must explain why the hook blocked.'
    )

    $checkContent = Get-Content -Raw -LiteralPath $checkPath
    Assert-True ($checkContent.Contains('[switch]$SkipFleet')) (
        'Unified check must expose a portable SkipFleet mode.'
    )
    $fleetCatalogEvidence = @($pass.evidence | Where-Object name -EQ 'fleet-catalog')
    Assert-True ($fleetCatalogEvidence.Count -eq 1) (
        'SkipFleet must remain visible in structured check results.'
    )
    Assert-True ($fleetCatalogEvidence[0].passed) (
        'A skipped fleet-catalog check must still report as passing.'
    )

    $gitDirectory = Join-Path $tempRoot '.git'
    $hookDirectory = Join-Path $gitDirectory 'hooks'
    New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null

    & $managerPath `
        -Mode Install `
        -ProjectRoot $core `
        -GitDirectory $gitDirectory
    $installedHook = Join-Path $hookDirectory 'pre-push'
    Assert-True (Test-Path -LiteralPath $installedHook -PathType Leaf) (
        'Install must create the pre-push hook.'
    )
    $installedContent = Get-Content -Raw -LiteralPath $installedHook
    Assert-True ($installedContent.Contains('projectD-core-owned-hook')) (
        'Installed hook must carry an ownership marker.'
    )
    Assert-True (-not $installedContent.Contains("`r`n")) (
        'Installed shell hook must use LF line endings.'
    )

    & $managerPath `
        -Mode Check `
        -ProjectRoot $core `
        -GitDirectory $gitDirectory

    & $managerPath `
        -Mode Uninstall `
        -ProjectRoot $core `
        -GitDirectory $gitDirectory
    Assert-True (-not (Test-Path -LiteralPath $installedHook)) (
        'Uninstall must remove the owned hook.'
    )

    Set-Content -LiteralPath $installedHook -Value '#!/bin/sh`nexit 0'
    $refused = $false
    try {
        & $managerPath `
            -Mode Install `
            -ProjectRoot $core `
            -GitDirectory $gitDirectory
    } catch {
        $refused = $true
    }
    Assert-True $refused 'Install must not overwrite an unowned hook.'
    Assert-True (Test-Path -LiteralPath $installedHook) (
        'Refused install must preserve the unowned hook.'
    )

    Write-Output 'GOVERNANCE_HOOK_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
