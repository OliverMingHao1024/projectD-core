[CmdletBinding()]
param(
    [string]$RemoteName,
    [string]$RemoteLocation
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $projectRoot 'scripts\ProjectD.GovernanceHook.psm1'
Import-Module $modulePath -Force

$result = Invoke-ProjectDGovernanceHook `
    -Event PrePush `
    -ProjectRoot $projectRoot
Write-Host "[projectD-core] $($result.message)"
foreach ($item in @($result.evidence)) {
    if ($result.decision -ne 'allow') {
        Write-Host "  - $item"
    }
}
if ($result.decision -eq 'block') { exit 1 }
exit 0
