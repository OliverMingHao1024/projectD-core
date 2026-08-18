Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ProjectDGovernanceHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PrePush', 'SessionStart')]
        [string]$Event,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [string[]]$CheckArguments = @(
            '-SkipFleet', '-SkipGlobal', '-SkipWiring'
        ),
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 60
    )

    $normalizedEvent = switch ($Event) {
        'PrePush' { 'pre-push' }
        'SessionStart' { 'session-start' }
    }
    if ($Event -ne 'PrePush') {
        return [pscustomobject]@{
            event = $normalizedEvent
            decision = 'warn'
            message = "No active adapter is configured for $normalizedEvent."
            evidence = @()
        }
    }

    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $constitution = Join-Path $root 'core\constitution\rules.md'
    $checkScript = Join-Path $root 'scripts\projectd-check.ps1'
    if (
        -not (Test-Path -LiteralPath $constitution -PathType Leaf) -or
        -not (Test-Path -LiteralPath $checkScript -PathType Leaf)
    ) {
        return [pscustomobject]@{
            event = $normalizedEvent
            decision = 'block'
            message = 'Repository is not an approved projectD-core root.'
            evidence = @($constitution, $checkScript)
        }
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        return [pscustomobject]@{
            event = $normalizedEvent
            decision = 'block'
            message = 'PowerShell 7 is required to run governance checks.'
            evidence = @()
        }
    }

    $tempRoot = Join-Path (
        [IO.Path]::GetTempPath()
    ) "projectd-governance-hook-$PID-$([guid]::NewGuid().ToString('N'))"
    $stdoutPath = Join-Path $tempRoot 'stdout.json'
    $stderrPath = Join-Path $tempRoot 'stderr.txt'
    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $arguments = @(
            '-NoProfile', '-File', $checkScript, '-ProjectRoot', $root
        ) + @($CheckArguments) + @('-Json')
        $process = Start-Process `
            -FilePath $pwsh.Source `
            -ArgumentList $arguments `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru `
            -WindowStyle Hidden
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit()
            return [pscustomobject]@{
                event = $normalizedEvent
                decision = 'block'
                message = (
                    "Governance checks exceeded the $TimeoutSeconds second " +
                    'timeout.'
                )
                evidence = @('Timed out before a valid report was produced.')
            }
        }
        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -Raw -LiteralPath $stdoutPath
        } else { '' }
        $stderr = ''
        if (Test-Path -LiteralPath $stderrPath) {
            $stderrContent = Get-Content -Raw -LiteralPath $stderrPath
            if ($null -ne $stderrContent) {
                $stderr = $stderrContent.ToString().Trim()
            }
        }
        $report = $null
        try {
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                $report = $stdout | ConvertFrom-Json
            }
        } catch {
            $report = $null
        }
        if (
            $process.ExitCode -eq 0 -and
            $null -ne $report -and
            $report.passed
        ) {
            return [pscustomobject]@{
                event = $normalizedEvent
                decision = 'allow'
                message = 'Repository-local governance checks passed.'
                evidence = @($report.checks)
            }
        }
        $details = if ($null -ne $report) {
            @(
                $report.checks |
                    Where-Object { -not $_.passed } |
                    ForEach-Object { "$($_.name): $($_.message)" }
            )
        } elseif ($stderr) {
            @($stderr)
        } else {
            @('Governance check did not return a valid JSON report.')
        }
        return [pscustomobject]@{
            event = $normalizedEvent
            decision = 'block'
            message = 'Repository-local governance checks failed.'
            evidence = $details
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

Export-ModuleMember -Function Invoke-ProjectDGovernanceHook
