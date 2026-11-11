[CmdletBinding()]
param(
    [ValidateSet('Show', 'Register', 'Unregister', 'Status')]
    [string]$Action = 'Show',
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
    [string]$At = '12:30',
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 30,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

<#
Runs governance-prune-local-evidence.ps1 -Mode Apply once a day as a
current-user Windows scheduled task, so .local/governance/ (one log, lock and
decision file per observed tool call, roughly 200 a day) does not grow
without bound.

- Show (default) only prints the task definition; it changes nothing.
- Register creates or replaces the task for the current user. No admin
  rights are needed and nothing runs elevated.
- StartWhenAvailable is on, so a run missed while the laptop was off happens
  at the next logon.
- The task only calls the existing prune script, so it inherits that script's
  limits: only past-retention evidence under .local/governance/ is removed.
#>

$ErrorActionPreference = 'Stop'
$taskName = 'projectD-governance-prune-local-evidence'

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
$pruneScript = Join-Path $root 'scripts\governance-prune-local-evidence.ps1'
if (-not (Test-Path -LiteralPath $pruneScript -PathType Leaf)) {
    throw "Prune script not found: $pruneScript"
}
$pwshPath = (Get-Command pwsh -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
$arguments = (
    '-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}" ' +
    '-Mode Apply -RetentionDays {1} -ProjectRoot "{2}"'
) -f $pruneScript, $RetentionDays, $root

$definition = [pscustomobject][ordered]@{
    task_name = $taskName
    daily_at = $At
    execute = $pwshPath
    arguments = $arguments
    run_level = 'Limited'
}

switch ($Action) {
    'Show' {
        return $definition
    }
    'Status' {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            return [pscustomobject]@{ task_name = $taskName; registered = $false }
        }
        $info = $task | Get-ScheduledTaskInfo
        return [pscustomobject][ordered]@{
            task_name = $taskName
            registered = $true
            state = [string]$task.State
            last_run = $info.LastRunTime
            last_result = $info.LastTaskResult
            next_run = $info.NextRunTime
        }
    }
    'Unregister' {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        return [pscustomobject]@{ task_name = $taskName; registered = $false }
    }
    'Register' {
        $taskAction = New-ScheduledTaskAction -Execute $pwshPath `
            -Argument $arguments -WorkingDirectory $root
        $trigger = New-ScheduledTaskTrigger -Daily -At $At
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        $principal = New-ScheduledTaskPrincipal `
            -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
            -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $taskAction `
            -Trigger $trigger -Settings $settings -Principal $principal `
            -Description 'Daily prune of past-retention projectD runtime governance evidence.' `
            -Force | Out-Null
        return $definition
    }
}
