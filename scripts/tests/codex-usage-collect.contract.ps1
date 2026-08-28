[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$collectPath = Join-Path $core 'scripts\codex-usage-collect.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "codex-usage-collect-$PID"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $Value | ConvertTo-Json -Depth 20 | Set-Content `
        -LiteralPath $Path -Encoding utf8 -NoNewline
}

function New-SessionMetaLine {
    param([Parameter(Mandatory)][string]$SessionId, [string]$Timestamp = '2026-08-26T10:00:00.000Z')
    return (
        [ordered]@{
            timestamp = $Timestamp
            type = 'session_meta'
            payload = [ordered]@{
                session_id = $SessionId
                id = $SessionId
                cwd = 'D:\workspaces\some-private-repo'
                git = [ordered]@{ repository_url = 'https://example.test/secret/repo.git' }
            }
        } | ConvertTo-Json -Depth 10 -Compress
    )
}

function New-TurnContextLine {
    param(
        [Parameter(Mandatory)][string]$TurnId,
        [string]$Model = 'gpt-5.6',
        [string]$Timestamp = '2026-08-26T10:00:01.000Z',
        [string]$Cwd = 'D:\workspaces\some-private-repo'
    )
    return (
        [ordered]@{
            timestamp = $Timestamp
            type = 'turn_context'
            payload = [ordered]@{ turn_id = $TurnId; model = $Model; cwd = $Cwd }
        } | ConvertTo-Json -Depth 10 -Compress
    )
}

function New-TokenCountLine {
    param(
        [Parameter(Mandatory)][string]$Timestamp,
        [int]$InputTokens = 100,
        [int]$CachedInputTokens = 20,
        [int]$OutputTokens = 30,
        [int]$ReasoningTokens = 5,
        [int]$UsedPercentPrimary = 25,
        [switch]$NoRateLimits
    )
    $payload = [ordered]@{
        type = 'token_count'
        info = [ordered]@{
            last_token_usage = [ordered]@{
                input_tokens = $InputTokens
                cached_input_tokens = $CachedInputTokens
                cache_write_input_tokens = 0
                output_tokens = $OutputTokens
                reasoning_output_tokens = $ReasoningTokens
            }
        }
    }
    if (-not $NoRateLimits) {
        $payload.rate_limits = [ordered]@{
            limit_id = 'codex'
            primary = [ordered]@{
                used_percent = $UsedPercentPrimary
                window_minutes = 300
                resets_at = 1787882400
            }
            secondary = [ordered]@{
                used_percent = 40
                window_minutes = 10080
                resets_at = 1788487200
            }
        }
    }
    return (
        [ordered]@{
            timestamp = $Timestamp
            type = 'event_msg'
            payload = $payload
        } | ConvertTo-Json -Depth 10 -Compress
    )
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Assert-True (
        Test-Path -LiteralPath $collectPath -PathType Leaf
    ) 'The Codex usage collector entrypoint must exist.'

    $projectRoot = Join-Path $tempRoot 'project'
    $accountId = 'acct_55555555555555555555555555555555'
    $deviceId = 'dev_dddddddddddddddddddddddddddddddd'
    Write-JsonFixture -Path (
        Join-Path $projectRoot '.local\governance\usage-account-profiles.json'
    ) -Value ([ordered]@{
        schema_version = 1
        accounts = @([ordered]@{
            provider = 'codex'; account_id = $accountId; alias = 'codex-collector-test'
            aliases = @(); email = 'codex-collector@example.test'
        })
    })
    Write-JsonFixture -Path (
        Join-Path $projectRoot '.local\governance\usage-device.json'
    ) -Value ([ordered]@{ schema_version = 1; device_id = $deviceId; environment = 'work' })
    $accountReadPath = Join-Path $projectRoot '.local\capture\codex-account-read.json'
    Write-JsonFixture -Path $accountReadPath -Value ([ordered]@{
        id = 1
        result = [ordered]@{
            account = [ordered]@{
                type = 'chatgpt'; email = 'codex-collector@example.test'; planType = 'plus'
            }
            requiresOpenaiAuth = $true
        }
    })

    $sessionRoot = Join-Path $tempRoot 'sessions\2026\08\26'
    $sessionId = 'aaaaaaaa-1111-2222-3333-444444444444'
    $turnA = 'turn-aaaa-0001'
    $turnB = 'turn-bbbb-0002'
    $lines = @(
        (New-SessionMetaLine -SessionId $sessionId),
        (New-TurnContextLine -TurnId $turnA -Timestamp '2026-08-26T10:00:01.000Z'),
        # Two token_count snapshots within the SAME turn: only the second
        # (final) one should ever reach the ledger.
        (New-TokenCountLine -Timestamp '2026-08-26T10:00:05.000Z' `
            -InputTokens 50 -OutputTokens 10 -UsedPercentPrimary 10),
        (New-TokenCountLine -Timestamp '2026-08-26T10:00:09.000Z' `
            -InputTokens 100 -OutputTokens 30 -UsedPercentPrimary 25),
        (New-TurnContextLine -TurnId $turnB -Timestamp '2026-08-26T10:01:00.000Z'),
        (New-TokenCountLine -Timestamp '2026-08-26T10:01:05.000Z' `
            -InputTokens 20 -OutputTokens 5 -UsedPercentPrimary 26),
        # A token_count with no rate_limits at all must still import usage.
        (New-TokenCountLine -Timestamp '2026-08-26T10:01:06.000Z' `
            -InputTokens 20 -OutputTokens 5 -NoRateLimits)
    )
    $sessionPath = Join-Path $sessionRoot "rollout-2026-08-26T10-00-00-$sessionId.jsonl"
    New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
    Set-Content -LiteralPath $sessionPath -Value ($lines -join "`n") -Encoding utf8 -NoNewline

    $result = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'sessions') `
        -AccountReadPath $accountReadPath | ConvertFrom-Json
    Assert-True (
        [int]$result.inserted -eq 2 -and [int]$result.failed -eq 0
    ) (
        'Exactly two turns must be inserted (one per turn_id), even though ' +
        'turn A had two intermediate token_count snapshots.'
    )

    $ledgerPath = Join-Path $projectRoot '.local\usage\codex-ledger.jsonl'
    $events = @(
        Get-Content -LiteralPath $ledgerPath | ForEach-Object { $_ | ConvertFrom-Json }
    )
    Assert-True ($events.Count -eq 2) 'The ledger must contain exactly two events.'
    $turnAEvent = @($events | Where-Object turn_id -ceq $turnA)[0]
    Assert-True (
        [long]$turnAEvent.usage.input_tokens.value -eq 100 -and
        [long]$turnAEvent.usage.output_tokens.value -eq 30
    ) (
        'Turn A must be recorded using its LAST token_count snapshot ' +
        '(100/30), not the first, intermediate one (50/10).'
    )

    $ledgerText = Get-Content -Raw -LiteralPath $ledgerPath
    Assert-True (
        $ledgerText -notmatch (
            '(?i)codex-collector@example\.test|secret/repo'
        )
    ) 'The ledger must never contain the git remote URL or email.'
    Assert-True (
        @($events | Where-Object { [string]$_.local_context.label -ceq 'some-private-repo' }).Count -eq 2
    ) (
        'Every event must carry local_context.label derived from the ' +
        'turn''s cwd folder basename when no session_index thread_name ' +
        'is available, for local-mode task attribution.'
    )

    $quotaPath = Join-Path $projectRoot '.local\usage\codex-quota-snapshot.json'
    Assert-True (
        Test-Path -LiteralPath $quotaPath -PathType Leaf
    ) 'A rate_limits-bearing token_count event must produce a quota snapshot.'
    $quota = Get-Content -Raw -LiteralPath $quotaPath | ConvertFrom-Json
    Assert-True (
        @($quota.windows).Count -eq 2 -and
        [string]$quota.identity.verification_status -ceq 'verified'
    ) 'The quota snapshot must carry both windows and a verified identity.'

    # --- replay: re-running must not double count or fail ---
    $replay = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'sessions') `
        -AccountReadPath $accountReadPath | ConvertFrom-Json
    Assert-True (
        [int]$replay.inserted -eq 0 -and [int]$replay.replayed -eq 2 -and
        [int]$replay.failed -eq 0
    ) 'Re-scanning the same session file must recognize both turns as replays.'
    Assert-True (
        @(Get-Content -LiteralPath $ledgerPath).Count -eq 2
    ) 'A replayed scan must not grow the ledger.'

    # --- -Since must exclude turns before the cutoff ---
    $sinceResult = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'sessions') `
        -AccountReadPath $accountReadPath `
        -Since '2026-08-26T10:00:30.000Z' | ConvertFrom-Json
    Assert-True (
        [int]$sinceResult.scanned -eq 2
    ) '-Since must bound collection to token_count events at or after the cutoff.'

    # --- session_index.jsonl thread_name takes priority over cwd ---
    $sessionIndexPath = Join-Path $tempRoot 'session_index.jsonl'
    $namedSessionId = 'bbbbbbbb-2222-3333-4444-555555555555'
    $namedTurn = 'turn-cccc-0003'
    Set-Content -LiteralPath $sessionIndexPath -Encoding utf8 -NoNewline -Value (
        @(
            # An earlier, stale entry for the same id must be overridden by
            # the later one -- later lines win on duplicate ids.
            ([ordered]@{ id = $namedSessionId; thread_name = 'stale title' } |
                ConvertTo-Json -Depth 5 -Compress),
            ([ordered]@{ id = $namedSessionId; thread_name = '優化 projectD Token 用量' } |
                ConvertTo-Json -Depth 5 -Compress)
        ) -join "`n"
    )
    $namedLines = @(
        (New-SessionMetaLine -SessionId $namedSessionId),
        (New-TurnContextLine -TurnId $namedTurn -Timestamp '2026-08-26T11:00:01.000Z'),
        (New-TokenCountLine -Timestamp '2026-08-26T11:00:05.000Z' `
            -InputTokens 8 -OutputTokens 2 -NoRateLimits)
    )
    $namedSessionPath = Join-Path $sessionRoot "rollout-2026-08-26T11-00-00-$namedSessionId.jsonl"
    Set-Content -LiteralPath $namedSessionPath -Value ($namedLines -join "`n") `
        -Encoding utf8 -NoNewline

    $namedResult = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'sessions') `
        -AccountReadPath $accountReadPath `
        -SessionIndexPath $sessionIndexPath | ConvertFrom-Json
    Assert-True (
        [int]$namedResult.inserted -eq 1 -and [int]$namedResult.failed -eq 0
    ) 'The session_index-labelled turn must import cleanly.'
    $namedEvents = @(
        Get-Content -LiteralPath $ledgerPath | ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object turn_id -ceq $namedTurn
    )
    Assert-True (
        $namedEvents.Count -eq 1 -and
        [string]$namedEvents[0].local_context.label -ceq '優化 projectD Token 用量'
    ) (
        'When session_index.jsonl has a thread_name for the session, it ' +
        'must be preferred over the cwd folder basename, and the LATEST ' +
        'entry must win when an id repeats.'
    )

    # --- no scratch files left behind ---
    Assert-True (
        @(Get-ChildItem -LiteralPath (Join-Path $projectRoot '.local\capture') `
            -Filter 'codex-turn-*.json' -File -ErrorAction SilentlyContinue).Count -eq 0 -and
        @(Get-ChildItem -LiteralPath (Join-Path $projectRoot '.local\capture') `
            -Filter 'codex-quota-*.json' -File -ErrorAction SilentlyContinue).Count -eq 0
    ) 'Per-turn scratch projection files must be cleaned up after import.'

    # --- content and no-model-call safety ---
    $implementationText = (Get-Content -Raw -LiteralPath $collectPath) `
        -replace '(?s)<#.*?#>', '' -replace '(?m)#.*$', ''
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?claude\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'The collector must not call the Claude CLI or make a network request.'
    Assert-True (
        $implementationText -notmatch '\.git\b|message\.content|reasoning\.text'
    ) (
        'The collector''s executable code must never reference git or ' +
        'message content fields (reading cwd is intentional -- it feeds ' +
        'the local-only local_context label, see usage-events.schema.json).'
    )
    Assert-True (
        $implementationText -notmatch '(?i)Get-Random'
    ) 'Collection must not depend on non-deterministic values.'

    Write-Output 'CODEX_USAGE_COLLECT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
