[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runPath = Join-Path $core 'scripts\usage-merge-run.ps1'
$mergeModulePath = Join-Path $core 'scripts\lib\UsageMerge.psm1'
$stateSchemaPath = Join-Path $core (
    'evals\schemas\usage-merge-state.schema.json'
)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "usage-merge-$PID"

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
    $Value | ConvertTo-Json -Depth 20 | Set-Content `
        -LiteralPath $Path -Encoding utf8 -NoNewline
}

function New-BatchFixture {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$DeviceId,
        [Parameter(Mandatory)][string]$Environment,
        [int]$InputTokens = 100,
        [int]$OutputTokens = 20,
        [string]$Model = 'gpt-5.6',
        [string]$GeneratedAt = '2026-08-28T03:00:00Z'
    )
    return [ordered]@{
        schema_version = 1
        policy_version = 'home-desktop-v1'
        redaction_version = 'v1'
        source_version = 'test-v1'
        generated_at = $GeneratedAt
        period = [ordered]@{
            start = '2026-08-01T00:00:00Z'
            end = '2026-09-01T00:00:00Z'
        }
        rows = @(
            [ordered]@{
                alias = $Alias
                provider = 'codex'
                model = $Model
                device_id = $DeviceId
                environment = $Environment
                run_count = 1
                input_tokens = [ordered]@{ status = 'observed'; value = $InputTokens }
                cached_input_tokens = [ordered]@{ status = 'unavailable'; value = $null }
                output_tokens = [ordered]@{ status = 'observed'; value = $OutputTokens }
                reasoning_tokens = [ordered]@{ status = 'unavailable'; value = $null }
                cache_creation_tokens = [ordered]@{ status = 'unavailable'; value = $null }
                estimated_cost_usd = [ordered]@{ status = 'unavailable'; value = $null }
            }
        )
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Assert-True (
        Test-Path -LiteralPath $runPath -PathType Leaf
    ) 'The usage merge run entrypoint must exist.'
    Assert-True (
        Test-Path -LiteralPath $mergeModulePath -PathType Leaf
    ) 'The usage merge module must exist.'
    Assert-True (
        Test-Path -LiteralPath $stateSchemaPath -PathType Leaf
    ) 'The usage merge state schema must exist.'

    # --- basic merge across two devices, same alias, distinguishable rows ---
    $projectA = Join-Path $tempRoot 'proj-a'
    New-Item -ItemType Directory -Path $projectA -Force | Out-Null
    $workBatchPath = Join-Path $projectA '.local\usage\import\work-batch.json'
    $homeBatchPath = Join-Path $projectA '.local\usage\import\home-batch.json'
    New-Item -ItemType Directory -Path (
        Join-Path $projectA '.local\usage\import'
    ) -Force | Out-Null
    Write-JsonFixture -Path $workBatchPath -Value (New-BatchFixture `
        -Alias 'personal-codex' `
        -DeviceId 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' `
        -Environment 'work' -InputTokens 100 -OutputTokens 20)
    Write-JsonFixture -Path $homeBatchPath -Value (New-BatchFixture `
        -Alias 'personal-codex' `
        -DeviceId 'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' `
        -Environment 'home' -InputTokens 50 -OutputTokens 10)

    $statePathA = Join-Path $projectA '.local\usage\merge\merge-state.json'
    $first = & $runPath `
        -ProjectRoot $projectA `
        -BatchPath @($workBatchPath, $homeBatchPath) `
        -StatePath $statePathA | ConvertFrom-Json
    Assert-True (
        [int]$first.rows -eq 2 -and
        @($first.results | Where-Object status -ceq 'merged').Count -eq 2
    ) 'Two batches from different devices must merge into two distinguishable rows.'

    $stateJson = Get-Content -Raw -LiteralPath $statePathA
    Assert-True (
        Test-Json -Json $stateJson -SchemaFile $stateSchemaPath -ErrorAction Stop
    ) 'The merge state must conform to its canonical schema.'
    $state = $stateJson | ConvertFrom-Json
    $workRow = @($state.totals | Where-Object environment -ceq 'work')[0]
    $homeRow = @($state.totals | Where-Object environment -ceq 'home')[0]
    Assert-True (
        [string]$workRow.device_id -ceq 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -and
        [string]$homeRow.device_id -ceq 'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -and
        [string]$workRow.alias -ceq 'personal-codex' -and
        [string]$homeRow.alias -ceq 'personal-codex' -and
        [long]$workRow.input_tokens.value -eq 100 -and
        [long]$homeRow.input_tokens.value -eq 50
    ) (
        'Rows sharing the same alias must remain distinguishable by ' +
        'device_id and environment.'
    )

    # --- idempotent replay: same batch twice must not double count ---
    $replay = & $runPath `
        -ProjectRoot $projectA `
        -BatchPath @($workBatchPath) `
        -StatePath $statePathA | ConvertFrom-Json
    Assert-True (
        [string]$replay.results[0].status -ceq 'replayed' -and
        [int]$replay.rows -eq 2
    ) 'Replaying the same batch must not duplicate its contribution.'
    $stateAfterReplay = Get-Content -Raw -LiteralPath $statePathA | ConvertFrom-Json
    $workRowAfterReplay = @(
        $stateAfterReplay.totals | Where-Object environment -ceq 'work'
    )[0]
    Assert-True (
        [long]$workRowAfterReplay.input_tokens.value -eq 100 -and
        [int]$workRowAfterReplay.run_count -eq 1
    ) 'A replayed batch must leave accumulated totals unchanged.'

    # --- a third, distinct batch from the work device must accumulate ---
    $secondWorkBatchPath = Join-Path $projectA (
        '.local\usage\import\work-batch-2.json'
    )
    Write-JsonFixture -Path $secondWorkBatchPath -Value (New-BatchFixture `
        -Alias 'personal-codex' `
        -DeviceId 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' `
        -Environment 'work' -InputTokens 25 -OutputTokens 5 `
        -GeneratedAt '2026-08-28T04:00:00Z')
    $third = & $runPath `
        -ProjectRoot $projectA `
        -BatchPath @($secondWorkBatchPath) `
        -StatePath $statePathA | ConvertFrom-Json
    Assert-True (
        [string]$third.results[0].status -ceq 'merged'
    ) 'A distinct new batch must be merged, not treated as a replay.'
    $stateAfterThird = Get-Content -Raw -LiteralPath $statePathA | ConvertFrom-Json
    $workRowAfterThird = @(
        $stateAfterThird.totals | Where-Object environment -ceq 'work'
    )[0]
    Assert-True (
        [long]$workRowAfterThird.input_tokens.value -eq 125 -and
        [int]$workRowAfterThird.run_count -eq 2
    ) 'A genuinely new batch must accumulate on top of prior totals.'

    # --- rejecting a malformed batch must not corrupt existing totals ---
    $malformedPath = Join-Path $projectA '.local\usage\import\malformed.json'
    Set-Content -LiteralPath $malformedPath -Value '{ "not": "a batch" }' `
        -Encoding utf8 -NoNewline
    $rejected = & $runPath `
        -ProjectRoot $projectA `
        -BatchPath @($malformedPath) `
        -StatePath $statePathA | ConvertFrom-Json
    Assert-True (
        [string]$rejected.results[0].status -ceq 'rejected' -and
        [int]$rejected.rows -eq 2
    ) 'A malformed batch must be rejected without altering existing totals.'

    # --- determinism: merge order must not change the final totals ---
    $stateB1 = Join-Path $projectA '.local\usage\merge\merge-state-b1.json'
    $stateB2 = Join-Path $projectA '.local\usage\merge\merge-state-b2.json'
    & $runPath -ProjectRoot $projectA `
        -BatchPath @($workBatchPath, $homeBatchPath) `
        -StatePath $stateB1 | Out-Null
    & $runPath -ProjectRoot $projectA `
        -BatchPath @($homeBatchPath, $workBatchPath) `
        -StatePath $stateB2 | Out-Null
    $totalsB1 = (
        Get-Content -Raw -LiteralPath $stateB1 | ConvertFrom-Json
    ).totals | ConvertTo-Json -Depth 20 -Compress
    $totalsB2 = (
        Get-Content -Raw -LiteralPath $stateB2 | ConvertFrom-Json
    ).totals | ConvertTo-Json -Depth 20 -Compress
    Assert-True (
        $totalsB1 -ceq $totalsB2
    ) 'Merging the same batches in a different order must yield identical totals.'

    # --- never writes to a per-device raw ledger ---
    $implementationText = @(
        Get-Content -Raw -LiteralPath $runPath
        Get-Content -Raw -LiteralPath $mergeModulePath
    ) -join "`n"
    Assert-True (
        $implementationText -notmatch '(?i)codex-ledger|claude-ledger'
    ) 'The merge tool must never read from or write to a per-device raw ledger.'
    Assert-True (
        $implementationText -notmatch (
            '(?im)^\s*(?:&\s*)?(?:codex|claude)\b|Invoke-RestMethod|Invoke-WebRequest'
        )
    ) 'Usage merge must not launch a model or call a provider endpoint.'
    Assert-True (
        (Get-Content -Raw -LiteralPath $runPath) -notmatch '(?i)Get-Random'
    ) 'Merge must not depend on non-deterministic values.'

    Write-Output 'USAGE_MERGE_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
