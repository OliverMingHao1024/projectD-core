[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Check')]
    [string]$Mode = 'Check',

    [string]$FleetPath
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'ProjectD.GovernanceWiring.psm1'
Import-Module $modulePath -Force

$core = Resolve-ProjectDCore -ScriptRoot $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FleetPath)) {
    $FleetPath = Join-Path $core 'fleet\fleet.json'
}
if (-not (Test-Path -LiteralPath $FleetPath -PathType Leaf)) {
    throw "Fleet file not found: $FleetPath"
}

$fleetItems = @(Get-Content -Raw -LiteralPath $FleetPath | ConvertFrom-Json)
if ($fleetItems.Count -eq 0) {
    throw "Fleet file contains no projects: $FleetPath"
}
$wiring = New-FleetGovernanceWiring `
    -Core $core `
    -FleetItems $fleetItems
$plan = @(
    Invoke-GovernanceWiring `
        -Resources $wiring.Resources `
        -Action $Mode `
        -StatePath $wiring.StatePath
)

if ($Mode -eq 'Check') {
    $issues = @($plan | Where-Object State -NE 'Compliant')
    foreach ($issue in $issues) {
        Write-Host (
            "[FAIL] $($issue.Resource.Path): $($issue.Message)"
        ) -ForegroundColor Red
    }
    if ($issues.Count -gt 0) {
        throw "Fleet governance check failed with $($issues.Count) issue(s)."
    }
}

$changed = if ($Mode -eq 'Apply') {
    @($plan | Where-Object Operation -NE 'None').Count
} else {
    0
}
Write-Host (
    "[PASS] Fleet governance: $($fleetItems.Count) project(s), " +
    "$($wiring.Resources.Count) entry file(s), $changed changed."
) -ForegroundColor Green
