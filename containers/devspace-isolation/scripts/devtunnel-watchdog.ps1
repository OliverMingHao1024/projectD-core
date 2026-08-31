<#
Watchdog for the devtunnel host process this deployment relies on
(`containers/devspace-isolation/README.md`'s "Exposing DevSpace publicly").

The devtunnel relay connection has been observed to silently drop while the
`devtunnel.exe` process itself keeps running (confirmed live: `devtunnel show`
reported "Host connections: 0" after ~30 hours of uptime, with the process
still alive) -- the existing "DevSpace Dev Tunnel" scheduled task only
restarts it at logon, so a mid-session drop stays broken until someone
notices and restarts it by hand. This script checks the relay connection and
restarts the host process only when it's actually disconnected.

Intended to run on a recurring schedule (see the -Install helper below),
not interactively.
#>

[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [Parameter(ParameterSetName = 'Check')]
    [string]$TunnelId = 'devspace-projectd',

    [Parameter(ParameterSetName = 'Check')]
    [string]$DevTunnelExe = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Microsoft.devtunnel_Microsoft.Winget.Source_8wekyb3d8bbwe\devtunnel.exe",

    [Parameter(ParameterSetName = 'Check')]
    [string]$LogPath = (Join-Path $env:TEMP 'devtunnel-watchdog.log'),

    [Parameter(ParameterSetName = 'Install', Mandatory)]
    [switch]$Install,

    [Parameter(ParameterSetName = 'Install')]
    [int]$IntervalMinutes = 5
)

function Write-Log {
    param([string]$Message)
    # Build the timestamp separately and concatenate -- do NOT put $Message
    # inside a composite format string passed to -f: devtunnel's raw output
    # can contain literal `{`/`}` (confirmed by testing), which -f then
    # tries to interpret as format placeholders and throws.
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $LogPath -Value "[$timestamp] $Message"
}

if ($PSCmdlet.ParameterSetName -eq 'Install') {
    # Registers this script itself on a recurring trigger. Separate from the
    # existing "DevSpace Dev Tunnel" ONLOGON task -- that one starts the
    # process fresh at logon; this one keeps an already-running process
    # actually connected in between logons.
    $scriptPath = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
    # [TimeSpan]::MaxValue serializes to an out-of-range Task Scheduler XML
    # duration (confirmed by testing: "Duration:P99999999DT23H59M59S" is
    # rejected) -- 10 years is effectively indefinite for this purpose and
    # is a value Task Scheduler actually accepts.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName 'DevSpace Dev Tunnel Watchdog' `
        -Action $action -Trigger $trigger -Settings $settings `
        -RunLevel Limited -Force | Out-Null
    Write-Output "Registered 'DevSpace Dev Tunnel Watchdog' (every $IntervalMinutes min)."
    return
}

if (-not (Test-Path -LiteralPath $DevTunnelExe)) {
    Write-Log "FATAL: devtunnel.exe not found at $DevTunnelExe"
    exit 1
}

$showOutput = & $DevTunnelExe show $TunnelId 2>&1
$hostConnLine = $showOutput | Select-String -Pattern 'Host connections\s*:\s*(\d+)'
if (-not $hostConnLine) {
    Write-Log "WARN: could not parse 'devtunnel show' output; leaving as-is. Raw: $($showOutput -join ' | ')"
    exit 1
}

$hostConnections = [int]$hostConnLine.Matches[0].Groups[1].Value
if ($hostConnections -gt 0) {
    # Healthy -- say nothing on the happy path to keep the log signal-only.
    exit 0
}

Write-Log "Host connections=0 -- relay link is down. Restarting devtunnel host."

Get-Process -Name devtunnel -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Log "Stopping stale devtunnel.exe (PID $($_.Id))"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

Start-Process -FilePath $DevTunnelExe -ArgumentList "host $TunnelId" `
    -WindowStyle Hidden
Start-Sleep -Seconds 5

$recheck = & $DevTunnelExe show $TunnelId 2>&1
$recheckLine = $recheck | Select-String -Pattern 'Host connections\s*:\s*(\d+)'
if ($recheckLine -and [int]$recheckLine.Matches[0].Groups[1].Value -gt 0) {
    Write-Log "Restart succeeded -- relay reconnected."
} else {
    Write-Log "WARN: restart attempted but relay still not connected. Raw: $($recheck -join ' | ')"
}
