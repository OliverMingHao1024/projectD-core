[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply')]
    [string]$Mode = 'Check',
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 30,
    [ValidateSet('claude', 'codex')]
    [string[]]$HostName = @('claude', 'codex'),
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
)

<#
Prunes old metadata-only runtime governance evidence under
.local/governance/ so it does not grow without bound (one log, one lock and
one decision file per observed tool call).

Only these files are candidates, and only when older than -RetentionDays:
- operation-hooks/<host>/<log>.json whose runner_state.status is "open"
  (completed), together with its .lock file and matching decision file;
- operation-hooks/<host>/<log>.json.lock with no matching log file;
- runtime-policy/<host>/decision-<call>.json with no matching log file
  (calls denied before an intent log was written);
- task-authorizations/<host>/*.json whose expires_at is also older than the
  retention window.

Kept on purpose: logs in requires-reconciliation (and their decisions and
locks), unreadable logs, *.error.log diagnostics, and anything newer than
the window. Check mode only reports. Nothing outside these directories is
touched, and reparse points are refused.
#>

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot does not exist.'
}
$cutoff = $Now.AddDays(-$RetentionDays)
$candidates = [Collections.Generic.List[object]]::new()

function Test-Older {
    param([Parameter(Mandatory)][IO.FileInfo]$File)
    return ([DateTimeOffset]$File.LastWriteTimeUtc) -lt $cutoff
}

function Get-SafeDirectoryFiles {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $Directory) {
        throw "Refusing to prune across a reparse point: $Directory"
    }
    return @(
        Get-ChildItem -LiteralPath $Directory -File -Force |
            Where-Object {
                -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
            }
    )
}

function Add-Candidate {
    param(
        [Parameter(Mandatory)][IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$Reason
    )
    $candidates.Add([pscustomobject]@{
        path = $File.FullName
        reason = $Reason
    })
}

foreach ($hostEntry in $HostName) {
    $governance = Join-Path $root '.local\governance'
    $hookDirectory = Join-Path $governance "operation-hooks\$hostEntry"
    $policyDirectory = Join-Path $governance "runtime-policy\$hostEntry"
    $authorizationDirectory = Join-Path $governance (
        "task-authorizations\$hostEntry"
    )

    $hookFiles = @(Get-SafeDirectoryFiles -Directory $hookDirectory)
    $policyFiles = @(Get-SafeDirectoryFiles -Directory $policyDirectory)
    $logs = @{}
    foreach ($file in $hookFiles | Where-Object Name -Like '*-call-*.json') {
        $logs[$file.Name] = $file
    }
    $keptCallSlugs = [Collections.Generic.HashSet[string]]::new()
    $prunedLogNames = [Collections.Generic.HashSet[string]]::new()

    foreach ($log in $logs.Values) {
        $callSlug = $log.BaseName.Substring($log.BaseName.IndexOf('call-'))
        $status = $null
        try {
            $status = [string](
                ([IO.File]::ReadAllText($log.FullName) | ConvertFrom-Json).runner_state.status
            )
        } catch {
            $status = $null
        }
        if ((Test-Older $log) -and $status -ceq 'open') {
            [void]$prunedLogNames.Add($log.Name)
            Add-Candidate $log 'completed operation log past retention'
        } else {
            [void]$keptCallSlugs.Add($callSlug)
        }
    }

    foreach ($lock in $hookFiles | Where-Object Name -Like '*.json.lock') {
        $logName = $lock.Name.Substring(0, $lock.Name.Length - '.lock'.Length)
        if (-not (Test-Older $lock)) { continue }
        if ($prunedLogNames.Contains($logName)) {
            Add-Candidate $lock 'lock of a pruned operation log'
        } elseif (-not $logs.ContainsKey($logName)) {
            Add-Candidate $lock 'orphaned lock past retention'
        }
    }

    foreach ($decision in $policyFiles | Where-Object Name -Like 'decision-call-*.json') {
        $callSlug = $decision.BaseName.Substring('decision-'.Length)
        if ((Test-Older $decision) -and -not $keptCallSlugs.Contains($callSlug)) {
            Add-Candidate $decision 'runtime policy decision past retention'
        }
    }

    foreach ($envelope in @(Get-SafeDirectoryFiles -Directory $authorizationDirectory) |
        Where-Object Extension -EQ '.json') {
        if (-not (Test-Older $envelope)) { continue }
        try {
            $expiresAt = [DateTimeOffset](
                ([IO.File]::ReadAllText($envelope.FullName) | ConvertFrom-Json).expires_at
            )
        } catch {
            continue
        }
        if ($expiresAt -lt $cutoff) {
            Add-Candidate $envelope 'task authorization expired past retention'
        }
    }
}

$deleted = 0
if ($Mode -eq 'Apply') {
    foreach ($candidate in $candidates) {
        try {
            Remove-Item -LiteralPath $candidate.path -Force
            $deleted++
        } catch {
            Write-Warning "Skipped (in use or not removable): $($candidate.path)"
        }
    }
}

foreach ($candidate in $candidates) {
    Write-Verbose "$($candidate.reason): $($candidate.path)"
}
[pscustomobject]@{
    mode = $Mode
    retention_days = $RetentionDays
    candidates = $candidates.Count
    deleted = $deleted
}
