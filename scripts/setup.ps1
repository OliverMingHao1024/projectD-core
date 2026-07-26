[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Check')]
    [string]$Mode = 'Apply'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'ProjectD.GovernanceWiring.psm1'
Import-Module $modulePath -Force

function Write-WiringPlan {
    param([Parameter(Mandatory)][object[]]$Plan)

    foreach ($item in $Plan) {
        $identity = if ($item.Resource.ResourceType -eq 'Environment') {
            "$($item.Resource.Scope):$($item.Resource.Name)"
        } else {
            $item.Resource.Path
        }
        Write-Host (
            "[{0}] {1} {2} — {3}" -f
                $item.State,
                $item.Operation,
                $identity,
                $item.Message
        )
    }
}

$core = Resolve-ProjectDCore -ScriptRoot $PSScriptRoot
$wiring = New-GlobalGovernanceWiring -Core $core

Write-Host ''
Write-Host "projectD-core GovernanceWiring ($Mode)" -ForegroundColor Cyan
Write-Host "Core: $core" -ForegroundColor DarkGray

$plan = @(
    Invoke-GovernanceWiring `
        -Resources $wiring.Resources `
        -Action $Mode `
        -StatePath $wiring.StatePath
)
Write-WiringPlan $plan

if ($Mode -eq 'Check') {
    $issues = @($plan | Where-Object State -NE 'Compliant')
    if ($issues.Count -gt 0) {
        throw "GovernanceWiring check failed with $($issues.Count) issue(s)."
    }
    Write-Host '[PASS] 全域治理接線符合 desired state。' -ForegroundColor Green
    return
}

$changed = @($plan | Where-Object Operation -NE 'None').Count
Write-Host (
    "[PASS] 全域治理接線已套用並驗證；$changed resource(s) changed."
) -ForegroundColor Green
Write-Host '可選本機歷程搜尋：.\scripts\setup-project-history.ps1（不會自動下載）'
Write-Host '回滾：pwsh -File scripts\uninstall.ps1'
