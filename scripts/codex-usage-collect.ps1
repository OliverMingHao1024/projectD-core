[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$TranscriptRoot,
    [Parameter(Mandatory)][string]$AccountReadPath,
    [string]$AccountProfilesPath,
    [string]$DeviceProfilePath,
    [string]$ExpectedAccountId,
    [string]$LedgerPath,
    [string]$QuotaSnapshotPath,
    [string]$Since
)

<#
Scans local Codex session rollout files
(~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl) for per-turn usage and
official quota/rate-limit data, and imports each through the existing
codex-usage-import.ps1 / codex-quota-import.ps1 pipeline. This is the
Codex counterpart to claude-usage-collect.ps1 and the same "collector"
boundary described in docs/specs/token-usage-monitoring.md: it only
ever reads already-written local rollout files, never starts the Codex
App Server, calls a model, or makes a network request.

Unlike the Claude collector, this script cannot resolve identity on
its own: the `account/read` JSON-RPC method the original identity
contract (#38) assumed exists is only reachable by speaking to a
running Codex App Server, and Phase 1 deliberately never starts one.
`codex login status` has no machine-readable, email-bearing output.
-AccountReadPath is therefore mandatory here -- the operator still
captures it once (see docs/operations/token-usage-monitoring.md) the
same way #39's original design intended.

Each import re-validates the full existing ledger, so a first full
historical scan can be slow; use -Since to bound a run to recent
turns, same as the Claude collector.

Only these fields are ever read out of a rollout record: session_meta's
session_id, turn_context's turn_id/model, and token_count's timestamp/
last_token_usage/rate_limits. Message content, reasoning text, and tool
call arguments/output elsewhere in the same file are never read.
#>

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force

function Read-SharedTranscriptText {
    <#
    An active Codex session keeps its rollout file open for exclusive
    writing on Windows. Reading with a shared, read-only FileStream
    (rather than [IO.File]::ReadAllBytes, which requests exclusive
    access) lets this scanner read a live session's file without
    waiting for Codex to close it or interrupting Codex's own writer.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open(
        $Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        $bytes = [byte[]]::new($stream.Length)
        $read = 0
        while ($read -lt $bytes.Length) {
            $chunk = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($chunk -le 0) { break }
            $read += $chunk
        }
        return [Text.UTF8Encoding]::new($false, $true).GetString($bytes, 0, $read)
    } finally {
        $stream.Dispose()
    }
}

function ConvertTo-CodexCollectUtcTimestamp {
    param([Parameter(Mandatory)]$Value)
    return ([DateTimeOffset]$Value).ToUniversalTime().ToString('o')
}

function ConvertTo-CodexQuotaWindows {
    param([Parameter(Mandatory)]$RateLimits)
    $windows = [Collections.Generic.List[object]]::new()
    foreach ($name in @('primary', 'secondary')) {
        $window = $RateLimits.$name
        if ($null -eq $window) { continue }
        if ($null -eq $window.used_percent) { continue }
        $windows.Add([ordered]@{
            limit_id = [string]$RateLimits.limit_id
            window = $name
            used_percent = [int][Math]::Round([double]$window.used_percent)
            window_duration_minutes = if ($null -eq $window.window_minutes) {
                $null
            } else { [long]$window.window_minutes }
            resets_at = if ($null -eq $window.resets_at) {
                $null
            } else { [long]$window.resets_at }
        })
    }
    return @($windows)
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot must be an existing directory.'
}
if ([string]::IsNullOrWhiteSpace($TranscriptRoot)) {
    $homeDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    if ([string]::IsNullOrWhiteSpace($homeDirectory)) {
        throw 'Unable to resolve the home directory for the Codex session root.'
    }
    $TranscriptRoot = Join-Path $homeDirectory '.codex\sessions'
}
if (-not (Test-Path -LiteralPath $TranscriptRoot -PathType Container)) {
    throw "Codex session root does not exist: $TranscriptRoot"
}
if (-not (Test-Path -LiteralPath $AccountReadPath -PathType Leaf)) {
    throw "AccountReadPath does not exist: $AccountReadPath"
}

$capturePath = Join-Path $root '.local\capture'
New-Item -ItemType Directory -Path $capturePath -Force | Out-Null

$sinceUtc = $null
if (-not [string]::IsNullOrWhiteSpace($Since)) {
    $sinceUtc = ([DateTimeOffset]$Since).ToUniversalTime()
}

$sessionFiles = @(
    Get-ChildItem -LiteralPath $TranscriptRoot -Filter 'rollout-*.jsonl' `
        -Recurse -File -ErrorAction SilentlyContinue
)

$counts = [ordered]@{
    scanned = 0; inserted = 0; replayed = 0; skipped = 0; failed = 0
    quota_updated = 0; quota_replayed = 0; quota_failed = 0
}
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Import-CodexUsageProjection {
    param([Parameter(Mandatory)]$Projection)
    $projectionPath = Join-Path $capturePath (
        "codex-turn-$([Guid]::NewGuid().ToString('N')).json"
    )
    $Projection | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $projectionPath -Encoding utf8 -NoNewline
    try {
        $importArgs = @{
            ProjectRoot = $root
            ProjectionPath = $projectionPath
            AccountReadPath = $AccountReadPath
        }
        foreach ($pair in @(
            @{ Name = 'AccountProfilesPath'; Value = $AccountProfilesPath },
            @{ Name = 'DeviceProfilePath'; Value = $DeviceProfilePath },
            @{ Name = 'ExpectedAccountId'; Value = $ExpectedAccountId },
            @{ Name = 'LedgerPath'; Value = $LedgerPath }
        )) {
            if (-not [string]::IsNullOrWhiteSpace($pair.Value)) {
                $importArgs[$pair.Name] = $pair.Value
            }
        }
        $result = & (Join-Path $PSScriptRoot 'codex-usage-import.ps1') @importArgs |
            ConvertFrom-Json
        switch ([string]$result.status) {
            'inserted' { $script:counts.inserted++ }
            'replayed' { $script:counts.replayed++ }
            default { $script:counts.skipped++ }
        }
    } catch {
        $script:counts.failed++
    } finally {
        if (Test-Path -LiteralPath $projectionPath -PathType Leaf) {
            Remove-Item -LiteralPath $projectionPath -Force
        }
    }
}

function Import-CodexQuotaProjectionFromWindows {
    param(
        [Parameter(Mandatory)][array]$Windows,
        [Parameter(Mandatory)][string]$CapturedAt
    )
    if ($Windows.Count -eq 0) { return }
    $quotaProjection = [ordered]@{
        schema_version = 1
        source = 'codex-app-server'
        captured_at = $CapturedAt
        windows = $Windows
    }
    $quotaProjectionPath = Join-Path $capturePath (
        "codex-quota-$([Guid]::NewGuid().ToString('N')).json"
    )
    $quotaProjection | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $quotaProjectionPath -Encoding utf8 -NoNewline
    try {
        $quotaArgs = @{
            ProjectRoot = $root
            ProjectionPath = $quotaProjectionPath
            AccountReadPath = $AccountReadPath
        }
        foreach ($pair in @(
            @{ Name = 'AccountProfilesPath'; Value = $AccountProfilesPath },
            @{ Name = 'DeviceProfilePath'; Value = $DeviceProfilePath },
            @{ Name = 'ExpectedAccountId'; Value = $ExpectedAccountId },
            @{ Name = 'SnapshotPath'; Value = $QuotaSnapshotPath }
        )) {
            if (-not [string]::IsNullOrWhiteSpace($pair.Value)) {
                $quotaArgs[$pair.Name] = $pair.Value
            }
        }
        $quotaResult = & (Join-Path $PSScriptRoot 'codex-quota-import.ps1') `
            @quotaArgs | ConvertFrom-Json
        switch ([string]$quotaResult.status) {
            'replayed' { $script:counts.quota_replayed++ }
            default { $script:counts.quota_updated++ }
        }
    } catch {
        $script:counts.quota_failed++
    } finally {
        if (Test-Path -LiteralPath $quotaProjectionPath -PathType Leaf) {
            Remove-Item -LiteralPath $quotaProjectionPath -Force
        }
    }
}

foreach ($file in $sessionFiles) {
    if (Test-PathHasReparsePoint -Root $TranscriptRoot -ResolvedPath $file.FullName) {
        continue
    }
    $text = try {
        Read-SharedTranscriptText -Path $file.FullName
    } catch { continue }

    $sessionId = $null
    $currentTurnId = $null
    $currentModel = $null
    # Codex can emit several token_count snapshots while a single turn is
    # still running; only the last one seen for a given turn_id reflects
    # that turn's final usage, so imports are deferred until the turn
    # boundary is known (a new turn_context, or end of file) instead of
    # firing on every snapshot -- otherwise the ledger's replay-vs-
    # conflict check sees the same turn_id with different token counts
    # and fails closed instead of recognizing a legitimate update.
    $pendingUsage = $null

    foreach ($line in @((($text -replace "`r", '') -split "`n"))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $record = try { $line | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        if ($null -eq $record) { continue }

        if ([string]$record.type -ceq 'session_meta') {
            $sessionId = [string]$record.payload.session_id
            continue
        }
        if ([string]$record.type -ceq 'turn_context') {
            if ($null -ne $pendingUsage -and (
                [string]$pendingUsage.turn_id -cne [string]$record.payload.turn_id
            )) {
                Import-CodexUsageProjection -Projection $pendingUsage
                $pendingUsage = $null
            }
            $currentTurnId = [string]$record.payload.turn_id
            $currentModel = [string]$record.payload.model
            continue
        }
        if (
            [string]$record.type -cne 'event_msg' -or
            [string]$record.payload.type -cne 'token_count'
        ) { continue }

        $info = $record.payload.info
        if ($null -eq $info -or $null -eq $info.last_token_usage) { continue }
        if (
            [string]::IsNullOrWhiteSpace($sessionId) -or
            [string]::IsNullOrWhiteSpace($currentTurnId) -or
            [string]::IsNullOrWhiteSpace($currentModel)
        ) { continue }

        $occurredAt = ConvertTo-CodexCollectUtcTimestamp $record.timestamp
        if ($null -ne $sinceUtc -and ([DateTimeOffset]$occurredAt) -lt $sinceUtc) {
            continue
        }

        $usage = $info.last_token_usage
        $pendingUsage = [ordered]@{
            schema_version = 1
            source = 'codex-app-server'
            captured_at = $occurredAt
            occurred_at = $occurredAt
            turn_status = 'completed'
            thread_id = $sessionId
            turn_id = $currentTurnId
            model = $currentModel
            usage = [ordered]@{
                input_tokens = if ($null -eq $usage.input_tokens) { 0 } else {
                    [long]$usage.input_tokens
                }
                cached_input_tokens = if ($null -eq $usage.cached_input_tokens) {
                    0
                } else { [long]$usage.cached_input_tokens }
                output_tokens = if ($null -eq $usage.output_tokens) { 0 } else {
                    [long]$usage.output_tokens
                }
                reasoning_tokens = if (
                    $null -eq $usage.reasoning_output_tokens
                ) { 0 } else { [long]$usage.reasoning_output_tokens }
                cache_creation_tokens = if (
                    $null -eq $usage.cache_write_input_tokens
                ) { 0 } else { [long]$usage.cache_write_input_tokens }
            }
        }
        $counts.scanned++

        if ($null -ne $record.payload.rate_limits) {
            $windows = @(ConvertTo-CodexQuotaWindows -RateLimits $record.payload.rate_limits)
            if ($windows.Count -gt 0) {
                Import-CodexQuotaProjectionFromWindows -Windows $windows -CapturedAt $occurredAt
            }
        }
    }
    if ($null -ne $pendingUsage) {
        Import-CodexUsageProjection -Projection $pendingUsage
        $pendingUsage = $null
    }
}

[pscustomobject]$counts | ConvertTo-Json -Compress
