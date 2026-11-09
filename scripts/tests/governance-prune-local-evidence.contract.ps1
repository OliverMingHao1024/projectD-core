[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$prune = Join-Path $core 'scripts\governance-prune-local-evidence.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "projectd-prune-$PID"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-Fixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][DateTime]$LastWrite
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content)
    (Get-Item -LiteralPath $Path).LastWriteTime = $LastWrite
}

try {
    $now = [DateTimeOffset]::new(2026, 11, 9, 0, 0, 0, [TimeSpan]::Zero)
    $old = $now.AddDays(-45).LocalDateTime
    $fresh = $now.AddDays(-2).LocalDateTime
    $governance = Join-Path $tempRoot '.local\governance'
    $hooks = Join-Path $governance 'operation-hooks\claude'
    $policy = Join-Path $governance 'runtime-policy\claude'
    $auth = Join-Path $governance 'task-authorizations\claude'
    $openLog = '{"runner_state":{"status":"open"}}'
    $pendingLog = '{"runner_state":{"status":"requires-reconciliation"}}'

    $paths = [ordered]@{
        oldOpenLog = Join-Path $hooks 'claude-call-aaa.json'
        oldOpenLock = Join-Path $hooks 'claude-call-aaa.json.lock'
        oldOpenDecision = Join-Path $policy 'decision-call-aaa.json'
        oldPendingLog = Join-Path $hooks 'claude-call-bbb.json'
        oldPendingLock = Join-Path $hooks 'claude-call-bbb.json.lock'
        oldPendingDecision = Join-Path $policy 'decision-call-bbb.json'
        oldDeniedDecision = Join-Path $policy 'decision-call-ccc.json'
        oldOrphanLock = Join-Path $hooks 'claude-call-ddd.json.lock'
        oldBrokenLog = Join-Path $hooks 'claude-call-eee.json'
        freshOpenLog = Join-Path $hooks 'claude-call-fff.json'
        freshDecision = Join-Path $policy 'decision-call-fff.json'
        errorLog = Join-Path $hooks 'claude-call-ggg.error.log'
        oldExpiredAuth = Join-Path $auth 'host-hook-session-old.json'
        freshExpiredAuth = Join-Path $auth 'host-hook-session-fresh.json'
        oldUnexpiredAuth = Join-Path $auth 'host-hook-session-live.json'
    }
    New-Fixture $paths.oldOpenLog $openLog $old
    New-Fixture $paths.oldOpenLock '' $old
    New-Fixture $paths.oldOpenDecision '{}' $old
    New-Fixture $paths.oldPendingLog $pendingLog $old
    New-Fixture $paths.oldPendingLock '' $old
    New-Fixture $paths.oldPendingDecision '{}' $old
    New-Fixture $paths.oldDeniedDecision '{}' $old
    New-Fixture $paths.oldOrphanLock '' $old
    New-Fixture $paths.oldBrokenLog '{not json' $old
    New-Fixture $paths.freshOpenLog $openLog $fresh
    New-Fixture $paths.freshDecision '{}' $fresh
    New-Fixture $paths.errorLog 'x' $old
    New-Fixture $paths.oldExpiredAuth (
        '{"expires_at":"' + $now.AddDays(-40).ToString('o') + '"}'
    ) $old
    New-Fixture $paths.freshExpiredAuth (
        '{"expires_at":"' + $now.AddDays(-1).ToString('o') + '"}'
    ) $fresh
    New-Fixture $paths.oldUnexpiredAuth (
        '{"expires_at":"' + $now.AddHours(1).ToString('o') + '"}'
    ) $old

    $checkResult = & $prune -ProjectRoot $tempRoot -Mode Check `
        -RetentionDays 30 -Now $now
    foreach ($path in $paths.Values) {
        Assert-True (Test-Path -LiteralPath $path) (
            "Check mode must not delete anything: $path"
        )
    }
    Assert-True ($checkResult.candidates -eq 6) (
        "Check mode must report exactly six prune candidates; got $($checkResult.candidates)."
    )
    Assert-True ($checkResult.deleted -eq 0) 'Check mode must report zero deletions.'

    $applyResult = & $prune -ProjectRoot $tempRoot -Mode Apply `
        -RetentionDays 30 -Now $now
    $expectedDeleted = @(
        'oldOpenLog', 'oldOpenLock', 'oldOpenDecision',
        'oldDeniedDecision', 'oldOrphanLock', 'oldExpiredAuth'
    )
    foreach ($key in $paths.Keys) {
        $exists = Test-Path -LiteralPath $paths[$key]
        if ($key -in $expectedDeleted) {
            Assert-True (-not $exists) "Apply must delete $key."
        } else {
            Assert-True $exists "Apply must keep $key."
        }
    }
    Assert-True ($applyResult.deleted -eq 6) (
        "Apply must report six deletions; got $($applyResult.deleted)."
    )

    $rejected = $false
    try {
        & $prune -ProjectRoot $tempRoot -Mode Apply -RetentionDays 0 -Now $now
    } catch {
        $rejected = $true
    }
    Assert-True $rejected 'A zero-day retention must be rejected.'

    Write-Output 'GOVERNANCE_PRUNE_LOCAL_EVIDENCE_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
