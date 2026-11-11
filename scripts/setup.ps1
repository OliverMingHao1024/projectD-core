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
        if ($item.Diff) {
            ($item.Diff -split "`n") | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
        }
    }
}

function Write-PruneScheduleHint {
    # Advisory only: a missing schedule never fails setup or Check.
    $scheduleScript = Join-Path $PSScriptRoot 'governance-prune-schedule.ps1'
    try {
        $status = & $scheduleScript -Action Status
    } catch {
        Write-Host "[SKIP] 無法查詢本機證據清理排程：$($_.Exception.Message)" `
            -ForegroundColor DarkGray
        return
    }
    if ($status.registered) {
        Write-Host "[PASS] 本機證據清理排程已註冊（$($status.task_name)）。" `
            -ForegroundColor Green
        return
    }
    Write-Host (
        '[WARN] 本機證據清理排程未註冊，.local/governance/ 會一直變大。' +
        '註冊：pwsh -File scripts\governance-prune-schedule.ps1 -Action Register'
    ) -ForegroundColor Yellow
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
    $issues = @($plan | Where-Object { $_.State -ne $_.ExpectedState })
    if ($issues.Count -gt 0) {
        $details = @(
            $issues | ForEach-Object {
                $identity = if (
                    $_.Resource.ResourceType -eq 'Environment'
                ) {
                    "$($_.Resource.Scope):$($_.Resource.Name)"
                } else {
                    $_.Resource.Path
                }
                "$identity — $($_.Message)"
            }
        ) -join '; '
        throw (
            "GovernanceWiring check failed with $($issues.Count) issue(s): " +
            $details
        )
    }
    Write-Host '[PASS] 全域治理接線符合 desired state。' -ForegroundColor Green
    Write-PruneScheduleHint
    return
}

$changed = @($plan | Where-Object Operation -NE 'None').Count
Write-Host (
    "[PASS] 全域治理接線已套用並驗證；$changed resource(s) changed."
) -ForegroundColor Green
Write-PruneScheduleHint
Write-Host '可選本機歷程搜尋：.\scripts\setup-project-history.ps1（不會自動下載）'
Write-Host '回滾：pwsh -File scripts\uninstall.ps1'
