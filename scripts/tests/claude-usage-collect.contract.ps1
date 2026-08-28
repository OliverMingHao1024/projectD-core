[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$collectPath = Join-Path $core 'scripts\claude-usage-collect.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "claude-usage-collect-$PID"

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

function New-TranscriptLine {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$Timestamp,
        [string]$Type = 'assistant',
        [bool]$IsSidechain = $false,
        [string]$Model = 'claude-sonnet-5',
        [int]$InputTokens = 2,
        [int]$CacheRead = 100,
        [int]$CacheCreation = 50,
        [int]$OutputTokens = 20,
        [int]$ThinkingTokens = 5,
        [bool]$IncludeUsage = $true
    )
    $record = [ordered]@{
        parentUuid = 'parent-0000'
        isSidechain = $IsSidechain
        message = [ordered]@{
            model = $Model
            id = "msg_$Uuid"
            type = 'message'
            role = 'assistant'
            content = @([ordered]@{
                type = 'text'
                text = 'this text must never reach the projection or ledger'
            })
        }
        type = $Type
        uuid = $Uuid
        timestamp = $Timestamp
        sessionId = $SessionId
        cwd = 'D:\workspaces\some-private-repo'
        gitBranch = 'feature/secret-project'
    }
    if ($IncludeUsage) {
        $record.message.usage = [ordered]@{
            input_tokens = $InputTokens
            cache_read_input_tokens = $CacheRead
            cache_creation_input_tokens = $CacheCreation
            output_tokens = $OutputTokens
            output_tokens_details = [ordered]@{ thinking_tokens = $ThinkingTokens }
        }
    }
    return ($record | ConvertTo-Json -Depth 20 -Compress)
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Assert-True (
        Test-Path -LiteralPath $collectPath -PathType Leaf
    ) 'The Claude usage collector entrypoint must exist.'

    $projectRoot = Join-Path $tempRoot 'project'
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

    $accountId = 'acct_44444444444444444444444444444444'
    $deviceId = 'dev_cccccccccccccccccccccccccccccccc'
    Write-JsonFixture -Path (
        Join-Path $projectRoot '.local\governance\usage-account-profiles.json'
    ) -Value ([ordered]@{
        schema_version = 1
        accounts = @([ordered]@{
            provider = 'claude'
            account_id = $accountId
            alias = 'collector-test'
            aliases = @()
            email = 'collector@example.test'
        })
    })
    Write-JsonFixture -Path (
        Join-Path $projectRoot '.local\governance\usage-device.json'
    ) -Value ([ordered]@{
        schema_version = 1
        device_id = $deviceId
        environment = 'work'
    })
    $accountReadPath = Join-Path $projectRoot '.local\capture\claude-account-read.json'
    Write-JsonFixture -Path $accountReadPath -Value ([ordered]@{
        auth = [ordered]@{
            loggedIn = $true
            authMethod = 'claude.ai'
            apiProvider = 'firstParty'
            subscriptionType = 'team'
            email = 'collector@example.test'
        }
        environmentState = [ordered]@{ apiBilling = $false; thirdParty = $false }
    })

    $transcriptRoot = Join-Path $tempRoot 'transcripts\proj'
    New-Item -ItemType Directory -Path $transcriptRoot -Force | Out-Null
    $sessionId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $lines = @(
        (New-TranscriptLine -SessionId $sessionId -Uuid 'turn-0001' `
            -Timestamp '2026-08-28T10:00:00.000Z' -InputTokens 10 -OutputTokens 5),
        # A user record: never usage-bearing, must be skipped.
        ([ordered]@{
            type = 'user'; uuid = 'turn-0002'; sessionId = $sessionId
            timestamp = '2026-08-28T10:01:00.000Z'
            message = [ordered]@{ role = 'user'; content = 'hello' }
        } | ConvertTo-Json -Depth 10 -Compress),
        # A sidechain record: must be skipped even though it has usage.
        (New-TranscriptLine -SessionId $sessionId -Uuid 'turn-0003' `
            -Timestamp '2026-08-28T10:02:00.000Z' -IsSidechain $true),
        # An assistant record with no usage block at all: must be skipped.
        (New-TranscriptLine -SessionId $sessionId -Uuid 'turn-0004' `
            -Timestamp '2026-08-28T10:03:00.000Z' -IncludeUsage $false),
        (New-TranscriptLine -SessionId $sessionId -Uuid 'turn-0005' `
            -Timestamp '2026-08-28T10:04:00.000Z' -InputTokens 7 -OutputTokens 3)
    )
    $transcriptPath = Join-Path $transcriptRoot "$sessionId.jsonl"
    Set-Content -LiteralPath $transcriptPath -Value ($lines -join "`n") `
        -Encoding utf8 -NoNewline

    $result = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'transcripts') `
        -SessionId $sessionId `
        -AccountReadPath $accountReadPath | ConvertFrom-Json
    Assert-True (
        [int]$result.scanned -eq 2 -and
        [int]$result.inserted -eq 2 -and
        [int]$result.failed -eq 0
    ) (
        'The collector must extract exactly the two genuine usage-bearing ' +
        'assistant turns, skipping user/sidechain/no-usage records.'
    )

    $ledgerPath = Join-Path $projectRoot '.local\usage\claude-ledger.jsonl'
    $events = @(
        Get-Content -LiteralPath $ledgerPath | ForEach-Object { $_ | ConvertFrom-Json }
    )
    Assert-True ($events.Count -eq 2) 'The ledger must contain exactly two events.'
    Assert-True (
        @($events | Where-Object { [long]$_.usage.input_tokens.value -eq 10 }).Count -eq 1 -and
        @($events | Where-Object { [long]$_.usage.input_tokens.value -eq 7 }).Count -eq 1
    ) 'Both genuine turns must be captured with their real token counts.'

    $ledgerText = Get-Content -Raw -LiteralPath $ledgerPath
    Assert-True (
        $ledgerText -notmatch (
            '(?i)this text must never|secret-project|collector@example\.test'
        )
    ) (
        'The ledger must never contain message content, git branch, or ' +
        'email -- only the allowlisted usage metadata fields (the cwd ' +
        'folder basename is intentionally allowed, as local_context.label).'
    )
    Assert-True (
        @($events | Where-Object { [string]$_.local_context.label -ceq 'some-private-repo' }).Count -eq 2
    ) (
        'Every event must carry local_context.label derived from the cwd ' +
        'folder basename, for local-mode task attribution.'
    )

    # No projection scratch files should be left behind.
    $captureDir = Join-Path $projectRoot '.local\capture'
    Assert-True (
        @(Get-ChildItem -LiteralPath $captureDir -Filter 'claude-turn-*.json' `
            -File -ErrorAction SilentlyContinue).Count -eq 0
    ) 'Per-turn scratch projection files must be cleaned up after import.'

    # --- replay: re-running against the same transcript must not double count ---
    $replay = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'transcripts') `
        -SessionId $sessionId `
        -AccountReadPath $accountReadPath | ConvertFrom-Json
    Assert-True (
        [int]$replay.inserted -eq 0 -and [int]$replay.replayed -eq 2
    ) (
        'Re-scanning the same transcript must recognize both turns as ' +
        'replays, not re-insert or fail them (captured_at must be ' +
        'deterministic per turn, not wall-clock time).'
    )
    Assert-True (
        @(Get-Content -LiteralPath $ledgerPath).Count -eq 2
    ) 'A replayed scan must not grow the ledger.'

    # --- -Since must exclude turns before the cutoff ---
    $sinceResult = & $collectPath `
        -ProjectRoot $projectRoot `
        -TranscriptRoot (Join-Path $tempRoot 'transcripts') `
        -SessionId $sessionId `
        -AccountReadPath $accountReadPath `
        -Since '2026-08-28T10:03:30.000Z' | ConvertFrom-Json
    Assert-True (
        [int]$sinceResult.scanned -eq 1
    ) '-Since must bound collection to turns at or after the cutoff.'

    # --- content and no-model-call safety ---
    $implementationText = Get-Content -Raw -LiteralPath $collectPath
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?codex\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'The collector must not call the Codex CLI or make a network request.'
    Assert-True (
        ($implementationText -replace '(?s)<#.*?#>', '' -replace '(?m)#.*$', '') -notmatch (
            '\.content\b|\.thinking\b|message\.role'
        )
    ) 'The collector''s executable code must never reference message content or role fields.'

    Write-Output 'CLAUDE_USAGE_COLLECT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
