[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$TranscriptRoot,
    [string]$SessionId,
    [string]$AccountProfilesPath,
    [string]$DeviceProfilePath,
    [string]$ExpectedAccountId,
    [string]$LedgerPath,
    [string]$Since,
    [string]$AccountReadPath
)

<#
Scans local Claude Code session transcripts
(~/.claude/projects/<project>/<session-id>.jsonl) for assistant-turn
usage metadata and imports each one through the existing
claude-usage-import.ps1 pipeline. This is the "collector" boundary
described in docs/specs/token-usage-monitoring.md: it only ever reads
already-written local transcript files, never starts Claude, calls a
model, or makes a network request other than the existing
`claude auth status --json` identity check (read-only, not a model
call). Re-running against the same transcripts is safe: the ledger's
own event-id digest already deduplicates replays, so this script does
not track a separate watermark.

Each import re-validates the full existing ledger against its schema
(the same cost the standalone importer already pays), so processing is
O(events already in the ledger) per new message -- fine for periodic
incremental runs against a handful of new messages, but a one-time
historical backfill against a long transcript can take a while. Use
-Since to bound a run to recent messages (e.g. run this once per
session end, or on a short interval, rather than rescanning full
history every time).

Only these fields are ever read out of a transcript record: sessionId,
message.uuid, message.timestamp, message.model, message.usage.*. The
transcript's `content`, `thinking`, and any tool input/output are never
copied into the projection, and the projection is validated against
claude-usage-projection.schema.json (additionalProperties: false)
before it can reach the importer.
#>

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force

function Test-PresentEnvironmentValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    return $normalized -notin @('', '0', 'false', 'no', 'off')
}

function Get-LiveClaudeAuthStatus {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        throw 'Claude CLI is unavailable.'
    }
    $raw = @(& claude auth status --json 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        throw 'Claude authentication status is unavailable.'
    }
    return $raw | ConvertFrom-Json
}

function ConvertTo-ClaudeCollectUtcTimestamp {
    param([Parameter(Mandatory)]$Value)
    return ([DateTimeOffset]$Value).ToUniversalTime().ToString('o')
}

function ConvertTo-ClaudeUsageProjection {
    <#
    Extracts only the allowlisted fields from one transcript record.
    Returns $null for any record that is not a usage-bearing assistant
    turn (sidechains, tool-result-only records, records without a
    usage block, etc.) -- those are simply not usage events, not a
    privacy filter working around content that should have been kept.
    #>
    param([Parameter(Mandatory)]$Record)

    if ([string]$Record.type -cne 'assistant') { return $null }
    if ([bool]$Record.isSidechain) { return $null }
    $message = $Record.message
    if ($null -eq $message -or $null -eq $message.usage) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$Record.sessionId)) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$Record.uuid)) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$message.model)) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$Record.timestamp)) { return $null }

    $usage = $message.usage
    $thinkingTokens = 0
    if (
        $null -ne $usage.output_tokens_details -and
        $null -ne $usage.output_tokens_details.thinking_tokens
    ) {
        $thinkingTokens = [long]$usage.output_tokens_details.thinking_tokens
    }
    $cacheRead = if ($null -eq $usage.cache_read_input_tokens) { 0 } else {
        [long]$usage.cache_read_input_tokens
    }
    $cacheCreation = if ($null -eq $usage.cache_creation_input_tokens) { 0 } else {
        [long]$usage.cache_creation_input_tokens
    }
    $inputTokens = if ($null -eq $usage.input_tokens) { 0 } else {
        [long]$usage.input_tokens
    }
    $outputTokens = if ($null -eq $usage.output_tokens) { 0 } else {
        [long]$usage.output_tokens
    }

    # captured_at is deliberately derived from the turn's own timestamp,
    # not wall-clock "now": this projection is built by re-scanning an
    # already-fixed historical transcript record, and identity capture
    # (see claude-usage-import.ps1) is keyed off captured_at, so it must
    # be stable across repeated runs for the same turn to be recognized
    # as a replay instead of a spurious "conflicting content" mismatch.
    $occurredAt = ConvertTo-ClaudeCollectUtcTimestamp $Record.timestamp
    $fields = [ordered]@{
        schema_version = 1
        source = 'claude-code-transcript'
        captured_at = $occurredAt
        occurred_at = $occurredAt
        session_id = [string]$Record.sessionId
        turn_id = [string]$Record.uuid
        model = [string]$message.model
        usage = [ordered]@{
            input_tokens = $inputTokens
            cached_input_tokens = $cacheRead
            output_tokens = $outputTokens
            reasoning_tokens = $thinkingTokens
            cache_creation_tokens = $cacheCreation
        }
    }
    # Local-only diagnostic hint (a project folder name), never carried
    # through the export gate or cross-device merge -- see local_context
    # in usage-events.schema.json / claude-usage-projection.schema.json.
    if (
        $Record.PSObject.Properties.Name -ccontains 'cwd' -and
        -not [string]::IsNullOrWhiteSpace([string]$Record.cwd)
    ) {
        $projectLabel = Split-Path -Leaf ([string]$Record.cwd)
        if (-not [string]::IsNullOrWhiteSpace($projectLabel)) {
            $fields.local_context = [ordered]@{ label = $projectLabel }
        }
    }
    return [pscustomobject]$fields
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
        throw 'Unable to resolve the home directory for the Claude transcript root.'
    }
    $TranscriptRoot = Join-Path $homeDirectory '.claude\projects'
}
if (-not (Test-Path -LiteralPath $TranscriptRoot -PathType Container)) {
    throw "Claude transcript root does not exist: $TranscriptRoot"
}

$capturePath = Join-Path $root '.local\capture'
New-Item -ItemType Directory -Path $capturePath -Force | Out-Null
if ([string]::IsNullOrWhiteSpace($AccountReadPath)) {
    # No pre-captured account-read fixture supplied: fall back to a live,
    # read-only identity check (not a model call), matching
    # claude-account.ps1's existing pattern.
    $accountReadPath = Join-Path $capturePath 'claude-account-read.json'
    $environmentState = [pscustomobject]@{
        apiBilling = (
            (Test-PresentEnvironmentValue $env:ANTHROPIC_API_KEY) -or
            (Test-PresentEnvironmentValue $env:ANTHROPIC_AUTH_TOKEN) -or
            (Test-PresentEnvironmentValue $env:CLAUDE_CODE_OAUTH_TOKEN)
        )
        thirdParty = (
            (Test-PresentEnvironmentValue $env:CLAUDE_CODE_USE_BEDROCK) -or
            (Test-PresentEnvironmentValue $env:CLAUDE_CODE_USE_VERTEX) -or
            (Test-PresentEnvironmentValue $env:CLAUDE_CODE_USE_FOUNDRY)
        )
    }
    $auth = Get-LiveClaudeAuthStatus
    [pscustomobject][ordered]@{
        auth = $auth
        environmentState = $environmentState
    } | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $accountReadPath -Encoding utf8 -NoNewline
} else {
    $accountReadPath = $AccountReadPath
}

$transcriptFiles = @(
    Get-ChildItem -LiteralPath $TranscriptRoot -Filter '*.jsonl' -Recurse -File `
        -ErrorAction SilentlyContinue
) | Where-Object {
    [string]::IsNullOrWhiteSpace($SessionId) -or
    $_.BaseName -ceq $SessionId
}

$sinceUtc = $null
if (-not [string]::IsNullOrWhiteSpace($Since)) {
    $sinceUtc = ([DateTimeOffset]$Since).ToUniversalTime()
}
$counts = [ordered]@{ scanned = 0; inserted = 0; replayed = 0; skipped = 0; failed = 0 }
$utf8 = [Text.UTF8Encoding]::new($false, $true)

foreach ($file in $transcriptFiles) {
    if (Test-PathHasReparsePoint -Root $TranscriptRoot -ResolvedPath $file.FullName) {
        continue
    }
    $text = try {
        $utf8.GetString([IO.File]::ReadAllBytes($file.FullName))
    } catch { continue }
    foreach ($line in @((($text -replace "`r", '') -split "`n"))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $record = try { $line | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        if ($null -eq $record) { continue }
        $projection = ConvertTo-ClaudeUsageProjection -Record $record
        if ($null -eq $projection) { continue }
        if ($null -ne $sinceUtc) {
            $occurred = [DateTimeOffset]$projection.occurred_at
            if ($occurred -lt $sinceUtc) { continue }
        }
        $counts.scanned++

        $projectionPath = Join-Path $capturePath (
            "claude-turn-$($projection.turn_id).json"
        )
        $projection | ConvertTo-Json -Depth 8 | Set-Content `
            -LiteralPath $projectionPath -Encoding utf8 -NoNewline
        try {
            $importArgs = @{
                ProjectRoot = $root
                ProjectionPath = $projectionPath
                AccountReadPath = $accountReadPath
            }
            if (-not [string]::IsNullOrWhiteSpace($AccountProfilesPath)) {
                $importArgs.AccountProfilesPath = $AccountProfilesPath
            }
            if (-not [string]::IsNullOrWhiteSpace($DeviceProfilePath)) {
                $importArgs.DeviceProfilePath = $DeviceProfilePath
            }
            if (-not [string]::IsNullOrWhiteSpace($ExpectedAccountId)) {
                $importArgs.ExpectedAccountId = $ExpectedAccountId
            }
            if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) {
                $importArgs.LedgerPath = $LedgerPath
            }
            $result = & (Join-Path $PSScriptRoot 'claude-usage-import.ps1') @importArgs |
                ConvertFrom-Json
            switch ([string]$result.status) {
                'inserted' { $counts.inserted++ }
                'replayed' { $counts.replayed++ }
                default { $counts.skipped++ }
            }
        } catch {
            $counts.failed++
        } finally {
            if (Test-Path -LiteralPath $projectionPath -PathType Leaf) {
                Remove-Item -LiteralPath $projectionPath -Force
            }
        }
    }
}

[pscustomobject]$counts | ConvertTo-Json -Compress
