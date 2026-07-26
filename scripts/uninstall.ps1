[CmdletBinding()]
param(
    [ValidateSet('Remove', 'Check')]
    [string]$Mode = 'Remove'
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

if ($Mode -eq 'Check') {
    $plan = @(
        Get-GovernanceWiringPlan `
            -Resources $wiring.Resources `
            -Action Remove `
            -StatePath $wiring.StatePath
    )
    Write-WiringPlan $plan
    $conflicts = @($plan | Where-Object Operation -EQ 'Conflict')
    if ($conflicts.Count -gt 0) {
        throw "GovernanceWiring remove preflight found $($conflicts.Count) conflict(s)."
    }
    Write-Host '[PASS] 移除預檢通過；尚未修改任何資源。' -ForegroundColor Green
    return
}

$plan = @(
    Invoke-GovernanceWiring `
        -Resources $wiring.Resources `
        -Action Remove `
        -StatePath $wiring.StatePath
)
Write-WiringPlan $plan
$changed = @($plan | Where-Object Operation -NE 'None').Count
Write-Host (
    "[PASS] 已移除並驗證 $changed 個 owned resource；repo 本身未刪除。"
) -ForegroundColor Green
