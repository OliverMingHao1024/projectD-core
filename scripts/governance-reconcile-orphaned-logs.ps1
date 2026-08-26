[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('codex', 'claude')]
    [string]$HostName,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaPath,
    [ValidateSet('completed', 'failed', 'aborted')]
    [string]$Outcome = 'aborted',
    [int]$MinimumAgeSeconds = 300,
    [switch]$WhatIf
)

<#
Appends a terminal `operation-finished` record (outcome: $Outcome) to any
durable operation log left in `requires-reconciliation` by
governance-host-operation-hook.ps1 -- e.g. the host process ended before
PostToolUse ever arrived, or PostToolUse's tool_input failed the tamper
check against the recorded intent. This only appends a new record;
record-1 and record-2 are never modified, preserving the append-only
evidence chain.

PostToolUse can legitimately arrive tens of seconds after PreToolUse (cold
process starts, a slow tool call). Reconciling a log while its real
PostToolUse is still in flight races that delivery: the late PostToolUse
then finds the operation already closed and fails with "Post event
conflicts with its durable result." -MinimumAgeSeconds (default 300)
skips any intent younger than that, so only logs from sessions that are
genuinely gone get reconciled.
#>

$ErrorActionPreference = 'Stop'
$maximumLogBytes = 1MB
$lockTimeout = [TimeSpan]::FromSeconds(10)
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Enter-LogLock {
    param([Parameter(Mandatory)][string]$Path)
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            return [IO.FileStream]::new(
                $Path,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None,
                1,
                [IO.FileOptions]::WriteThrough
            )
        } catch [IO.IOException] {
            if ($stopwatch.Elapsed -ge $lockTimeout) {
                throw 'Timed out waiting for the operation-log writer.'
            }
            Start-Sleep -Milliseconds 50
        }
    } while ($true)
}

function Write-DurableLog {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Schema
    )
    $json = $Document | ConvertTo-Json -Depth 32
    if (-not (Test-Json -Json $json -SchemaFile $Schema -ErrorAction Stop)) {
        throw 'Generated operation log does not conform to its schema.'
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    if ($bytes.Length -gt $maximumLogBytes) {
        throw 'Generated operation log exceeds its size limit.'
    }
    $temporary = Join-Path (Split-Path -Parent $Path) (
        ".write-$([Guid]::NewGuid().ToString('N')).tmp"
    )
    try {
        $stream = [IO.FileStream]::new(
            $temporary,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None,
            4096,
            [IO.FileOptions]::WriteThrough
        )
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }
        [IO.File]::Move($temporary, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force
$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot does not exist.'
}
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $root 'evals\schemas\governance-operation-logs.schema.json'
}
$schemaFullPath = [IO.Path]::GetFullPath($SchemaPath)
if (-not (Test-Path -LiteralPath $schemaFullPath -PathType Leaf)) {
    throw 'SchemaPath is missing.'
}

$logDirectory = [IO.Path]::GetFullPath((Join-Path $root ".local\governance\operation-hooks\$HostName"))
if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
    Write-Output "No log directory for host '$HostName'; nothing to reconcile."
    return
}

$candidates = Get-ChildItem -LiteralPath $logDirectory -Filter '*.json' -File
$reconciled = 0
$skipped = 0

foreach ($file in $candidates) {
    $logPath = $file.FullName
    $lockPath = "$logPath.lock"
    $lock = Enter-LogLock -Path $lockPath
    try {
        $json = $utf8.GetString([IO.File]::ReadAllBytes($logPath))
        if (-not (Test-Json -Json $json -SchemaFile $schemaFullPath -ErrorAction Stop)) {
            Write-Warning "Skipping $($file.Name): does not conform to schema."
            $skipped++
            continue
        }
        $document = $json | ConvertFrom-Json
        if ([string]$document.runner_state.status -ne 'requires-reconciliation') {
            continue
        }
        $records = @($document.records)
        $intentAge = [DateTimeOffset]::UtcNow -
            [DateTimeOffset]$records[1].occurred_at
        if ($intentAge.TotalSeconds -lt $MinimumAgeSeconds) {
            Write-Output (
                "Skipping $($file.Name): intent is only " +
                "$([int]$intentAge.TotalSeconds)s old, PostToolUse may " +
                "still be in flight (minimum age $MinimumAgeSeconds`s)."
            )
            $skipped++
            continue
        }
        $last = $records[$records.Count - 1]
        $nextSequence = [int]$last.sequence + 1
        $newRecord = [pscustomobject][ordered]@{
            record_id = "record-$nextSequence"
            sequence = $nextSequence
            previous_record_id = [string]$last.record_id
            occurred_at = [DateTimeOffset]::UtcNow.ToString('o')
            operation_id = [string]$records[0].operation_id
            type = 'operation-finished'
            outcome = $Outcome
        }
        $document.records = @($records) + $newRecord
        $document.runner_state.status = $Outcome
        $document.runner_state.pending_effect_id = $null
        $document.runner_state.last_sequence = $nextSequence

        if ($WhatIf) {
            Write-Output "Would reconcile $($file.Name) -> outcome=$Outcome (sequence $nextSequence)"
        } else {
            Write-DurableLog -Document $document -Path $logPath -Schema $schemaFullPath
            Write-Output "Reconciled $($file.Name) -> outcome=$Outcome (sequence $nextSequence)"
        }
        $reconciled++
    } finally {
        $lock.Dispose()
    }
}

Write-Output "Done. Reconciled: $reconciled. Skipped (schema issues): $skipped. Scanned: $($candidates.Count)."
