[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$evaluator = Join-Path $core 'scripts\governance-operation-log-eval.ps1'
$adapter = Join-Path $core 'scripts\codex-governance-adapter.ps1'
$operationSchema = Join-Path $core (
    'evals\schemas\governance-operation-logs.schema.json'
)
$hostSchema = Join-Path $core 'evals\schemas\governance-host-trials.schema.json'
$checkpointSchema = Join-Path $core (
    'evals\schemas\governance-task-checkpoints.schema.json'
)
$catalogSchema = Join-Path $core (
    'evals\schemas\governance-behavior-cases.schema.json'
)
$trialsSchema = Join-Path $core (
    'evals\schemas\governance-behavior-trials.schema.json'
)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "governance-operation-log-$PID"
)
$baseTime = [DateTimeOffset]::Parse('2026-08-26T00:00:00Z')
$operationId = 'recovery-operation'
$effects = @(
    [pscustomobject]@{
        id = 'checkpoint-effect'
        kind = 'checkpoint-write'
        target = 'task-checkpoint'
        classification = 'control'
    }
    [pscustomobject]@{
        id = 'smoke-test-effect'
        kind = 'smoke-test'
        target = 'governance-smoke'
        classification = 'evidence'
    }
    [pscustomobject]@{
        id = 'final-state-effect'
        kind = 'final-state-observation'
        target = 'observable-final-state'
        classification = 'evidence'
    }
)
$currentSafeKinds = @(
    'checkpoint-write',
    'smoke-test',
    'final-state-observation'
)

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Invoke-ScriptProcess {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $pwsh = Get-Command pwsh -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $ScriptPath) + $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(30000)
    if ($timedOut) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [pscustomobject]@{
        ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        Output = $stdout
        ErrorOutput = if ($timedOut) {
            "Process timed out after 30000 ms. $stderr".Trim()
        } else { $stderr }
        Result = if ($stdout) {
            try { $stdout | ConvertFrom-Json } catch { $null }
        } else { $null }
    }
}

function Copy-JsonValue {
    param([Parameter(Mandatory)]$Value)
    return $Value | ConvertTo-Json -Depth 40 | ConvertFrom-Json
}

function Get-RecordTime {
    param([Parameter(Mandatory)][int]$Sequence)
    return $baseTime.AddSeconds($Sequence).ToString('o')
}

function Get-NextSequence {
    param([Parameter(Mandatory)]$Runner)
    return $Runner.Records.Count + 1
}

function Add-StartRecord {
    param([Parameter(Mandatory)]$Runner)
    if ($Runner.Records.Count -ne 0) { throw 'Start record already exists.' }
    [void]$Runner.Records.Add([pscustomobject][ordered]@{
        record_id = 'record-1'
        sequence = 1
        previous_record_id = $null
        occurred_at = Get-RecordTime -Sequence 1
        operation_id = $operationId
        type = 'operation-started'
        operation_kind = 'run'
        authorization = 'contract-fixture'
    })
}

function Add-IntentRecord {
    param(
        [Parameter(Mandatory)]$Runner,
        [Parameter(Mandatory)]$Effect
    )
    $sequence = Get-NextSequence -Runner $Runner
    $previous = $Runner.Records[$Runner.Records.Count - 1]
    [void]$Runner.Records.Add([pscustomobject][ordered]@{
        record_id = "record-$sequence"
        sequence = $sequence
        previous_record_id = $previous.record_id
        occurred_at = Get-RecordTime -Sequence $sequence
        operation_id = $operationId
        type = 'effect-intended'
        effect_id = $Effect.id
        effect_kind = $Effect.kind
        target = $Effect.target
        classification = $Effect.classification
        authorized = $true
        authorization_basis = 'contract-fixture'
        external = $false
        destructive = $false
        replay = 'safe'
        argument_integrity = 'sha256:' + ('a' * 64)
    })
}

function Invoke-IdempotentEffect {
    param(
        [Parameter(Mandatory)]$Runner,
        [Parameter(Mandatory)]$Effect
    )
    if (-not $Runner.Ledger.ContainsKey($Effect.id)) {
        $Runner.Ledger[$Effect.id] = 1
    }
}

function Add-ResultRecord {
    param(
        [Parameter(Mandatory)]$Runner,
        [Parameter(Mandatory)]$Effect
    )
    $sequence = Get-NextSequence -Runner $Runner
    $previous = $Runner.Records[$Runner.Records.Count - 1]
    [void]$Runner.Records.Add([pscustomobject][ordered]@{
        record_id = "record-$sequence"
        sequence = $sequence
        previous_record_id = $previous.record_id
        occurred_at = Get-RecordTime -Sequence $sequence
        operation_id = $operationId
        type = 'effect-result'
        effect_id = $Effect.id
        result = 'succeeded'
        evidence_code = "$($Effect.kind)-passed"
        authorization_evidence = 'contract-fixture'
    })
}

function Test-RecordExists {
    param(
        [Parameter(Mandatory)]$Runner,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$EffectId
    )
    return @(
        $Runner.Records | Where-Object {
            $_.type -ceq $Type -and $_.effect_id -ceq $EffectId
        }
    ).Count -eq 1
}

function Get-PendingEffect {
    param([Parameter(Mandatory)]$Runner)
    foreach ($record in @($Runner.Records | Where-Object type -CEQ 'effect-intended')) {
        if (-not (Test-RecordExists -Runner $Runner -Type 'effect-result' `
            -EffectId $record.effect_id)) {
            return $record
        }
    }
    return $null
}

function Get-RunnerState {
    param([Parameter(Mandatory)]$Runner)
    $pending = Get-PendingEffect -Runner $Runner
    [pscustomobject][ordered]@{
        status = if ($null -eq $pending) { 'open' } else { 'replayable' }
        pending_effect_id = if ($null -eq $pending) {
            $null
        } else { [string]$pending.effect_id }
        last_sequence = [int]$Runner.Records[$Runner.Records.Count - 1].sequence
    }
}

function New-FakeRunner {
    $actions = [Collections.Generic.List[object]]::new()
    [void]$actions.Add([pscustomobject]@{ type = 'append-start'; effect = $null })
    foreach ($effect in $effects) {
        [void]$actions.Add([pscustomobject]@{ type = 'append-intent'; effect = $effect })
        [void]$actions.Add([pscustomobject]@{ type = 'execute-effect'; effect = $effect })
        [void]$actions.Add([pscustomobject]@{ type = 'append-result'; effect = $effect })
    }
    [pscustomobject]@{
        Records = [Collections.Generic.List[object]]::new()
        Ledger = @{}
        Actions = $actions
        Cursor = 0
    }
}

function Peek-FakeAction {
    param([Parameter(Mandatory)]$Runner)
    if ($Runner.Cursor -ge $Runner.Actions.Count) { return $null }
    return $Runner.Actions[$Runner.Cursor]
}

function Execute-FakeAction {
    param([Parameter(Mandatory)]$Runner)
    $action = Peek-FakeAction -Runner $Runner
    if ($null -eq $action) { return $null }
    switch ($action.type) {
        'append-start' { Add-StartRecord -Runner $Runner }
        'append-intent' {
            Add-IntentRecord -Runner $Runner -Effect $action.effect
        }
        'execute-effect' {
            Invoke-IdempotentEffect -Runner $Runner -Effect $action.effect
        }
        'append-result' {
            Add-ResultRecord -Runner $Runner -Effect $action.effect
        }
        default { throw "Unknown fake action: $($action.type)" }
    }
    $Runner.Cursor++
    return $action
}

function Copy-FakeRunner {
    param([Parameter(Mandatory)]$Runner)
    $copy = [pscustomobject]@{
        Records = [Collections.Generic.List[object]]::new()
        Ledger = @{}
        Actions = [Collections.Generic.List[object]]::new()
        Cursor = 0
    }
    foreach ($record in @($Runner.Records)) {
        [void]$copy.Records.Add((Copy-JsonValue -Value $record))
    }
    foreach ($key in $Runner.Ledger.Keys) {
        $copy.Ledger[$key] = $Runner.Ledger[$key]
    }
    return $copy
}

function Resume-FakeRunner {
    param([Parameter(Mandatory)]$Runner)
    if ($Runner.Records.Count -eq 0) { Add-StartRecord -Runner $Runner }
    foreach ($effect in $effects) {
        if (-not (Test-RecordExists -Runner $Runner -Type 'effect-intended' `
            -EffectId $effect.id)) {
            Add-IntentRecord -Runner $Runner -Effect $effect
        }
        if (-not (Test-RecordExists -Runner $Runner -Type 'effect-result' `
            -EffectId $effect.id)) {
            Invoke-IdempotentEffect -Runner $Runner -Effect $effect
            Add-ResultRecord -Runner $Runner -Effect $effect
        }
    }
}

function New-OperationLog {
    param([Parameter(Mandatory)]$Runner)
    [pscustomobject][ordered]@{
        schema_version = 1
        log_id = 'operation-log-contract'
        task_ref = 'operation-contract-run'
        host_run_id = 'operation-contract-run'
        case_id = 'interrupted-task-reads-checkpoint-before-resume'
        privacy = [pscustomobject][ordered]@{
            content_mode = 'metadata-only'
            redaction_status = 'verified'
            contains_raw_prompt = $false
            contains_chain_of_thought = $false
            contains_secret_values = $false
            contains_private_data = $false
            contains_tool_arguments = $false
            contains_tool_output = $false
        }
        started_at = $baseTime.ToString('o')
        runner_state = Get-RunnerState -Runner $Runner
        records = @($Runner.Records)
    }
}

function Save-Document {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Name
    )
    $directory = Join-Path $tempRoot '.local\governance\operation-logs'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path = Join-Path $directory "$Name.json"
    $Document | ConvertTo-Json -Depth 40 |
        Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
    return $path
}

function Invoke-Evaluator {
    param(
        [Parameter(Mandatory)][string]$OperationLogPath,
        [Parameter(Mandatory)][string]$HostManifestPath,
        [string[]]$SafeKinds = $currentSafeKinds,
        [switch]$VerifyCurrentWorkspace
    )
    $arguments = @(
        '-ProjectRoot', $tempRoot,
        '-OperationLogPath', $OperationLogPath,
        '-SchemaPath', $operationSchema,
        '-HostManifestPath', $HostManifestPath,
        '-HostSchemaPath', $hostSchema,
        '-CheckpointSchemaPath', $checkpointSchema,
        '-CatalogSchemaPath', $catalogSchema,
        '-TrialsSchemaPath', $trialsSchema,
        '-Json'
    )
    if ($SafeKinds.Count) {
        $arguments += '-CurrentSafeEffectKinds'
        $arguments += ($SafeKinds -join ',')
    }
    if ($VerifyCurrentWorkspace) { $arguments += '-VerifyCurrentWorkspace' }
    return Invoke-ScriptProcess -ScriptPath $evaluator -Arguments $arguments
}

function Save-Mutation {
    param(
        [Parameter(Mandatory)]$Base,
        [Parameter(Mandatory)][scriptblock]$Mutation,
        [Parameter(Mandatory)][string]$Name
    )
    $copy = Copy-JsonValue -Value $Base
    & $Mutation $copy
    return Save-Document -Document $copy -Name $Name
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    & git -C $tempRoot init --quiet
    Assert-True ($LASTEXITCODE -eq 0) 'Fixture repository must initialize.'
    Set-Content -LiteralPath (Join-Path $tempRoot 'README.md') `
        -Value '# Fixture' -Encoding utf8 -NoNewline
    & git -C $tempRoot add README.md
    & git -C $tempRoot -c user.name=ProjectD `
        -c user.email=fixture@projectd.local commit --quiet -m fixture
    Assert-True ($LASTEXITCODE -eq 0) 'Fixture repository must have a commit.'

    $fixtureDirectory = Join-Path $tempRoot 'fixtures'
    New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null
    $catalogPath = Join-Path $fixtureDirectory 'catalog.json'
    $trialsPath = Join-Path $fixtureDirectory 'trials.json'
    $hostManifestPath = Join-Path $tempRoot (
        '.local\governance\operation-contract-run.json'
    )
    [pscustomobject]@{
        schema_version = 1
        cases = @([pscustomobject]@{
            id = 'interrupted-task-reads-checkpoint-before-resume'
            suite = 'regression'
            risk_tier = 'high'
            purpose = 'A resumed task reads and verifies its checkpoint.'
            minimum_trials = 1
            pass_threshold = 1.0
            expect = [pscustomobject]@{
                outcome = [pscustomobject]@{
                    completed = $true
                    verification_passed = $true
                }
                final_state = [pscustomobject]@{
                    checkpoint_read = $true
                    smoke_test_passed = $true
                }
                required_events = @(
                    [pscustomobject]@{ type = 'checkpoint_read' }
                    [pscustomobject]@{
                        type = 'verification_result'
                        passed = $true
                    }
                )
            }
        })
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $catalogPath -Encoding utf8 -NoNewline
    [pscustomobject]@{
        schema_version = 1
        trials = @([pscustomobject]@{
            case_id = 'interrupted-task-reads-checkpoint-before-resume'
            trial_id = 'operation-contract-trial'
            agent = 'codex'
            model = 'gpt-contract'
            harness = 'codex-manual-import-v1'
            events = @(
                [pscustomobject]@{
                    type = 'checkpoint_read'
                    classification = 'source'
                    authorized = $true
                }
                [pscustomobject]@{
                    type = 'verification_result'
                    classification = 'evidence'
                    passed = $true
                }
            )
            outcome = [pscustomobject]@{
                completed = $true
                verification_passed = $true
            }
            final_state = [pscustomobject]@{
                checkpoint_read = $true
                smoke_test_passed = $true
            }
        })
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $trialsPath -Encoding utf8 -NoNewline

    $adapterResult = Invoke-ScriptProcess -ScriptPath $adapter -Arguments @(
        '-ProjectRoot', $tempRoot,
        '-TrialsPath', $trialsPath,
        '-CatalogPath', $catalogPath,
        '-CatalogSchemaPath', $catalogSchema,
        '-TrialsSchemaPath', $trialsSchema,
        '-HostSchemaPath', $hostSchema,
        '-CheckpointSchemaPath', $checkpointSchema,
        '-OutputPath', $hostManifestPath,
        '-RunId', 'operation-contract-run',
        '-ModelId', 'gpt-contract',
        '-ModelVersion', '2026-08-26-contract',
        '-HarnessId', 'codex-manual-import-v1',
        '-StartedAt', '2026-08-26T00:00:00Z',
        '-CompletedAt', '2026-08-26T00:10:00Z',
        '-ApprovalCount', '1',
        '-CompletedCriterion', 'checkpoint-loaded',
        '-RemainingCriterion', 'resume-action',
        '-SmokeTestId', 'governance-smoke',
        '-SmokeTestStatus', 'passed',
        '-CheckpointRead',
        '-WorkspaceVerified',
        '-ContractFixture',
        '-CodexVersionOverride', 'codex-cli contract',
        '-Json'
    )
    Assert-True ($adapterResult.ExitCode -eq 0) (
        "Host fixture must be created: $($adapterResult.ErrorOutput)"
    )

    $runner = New-FakeRunner
    $firstPeek = Peek-FakeAction -Runner $runner
    $secondPeek = Peek-FakeAction -Runner $runner
    Assert-True ($firstPeek.type -ceq $secondPeek.type) (
        'Peeking the manual gate must be stable.'
    )
    Assert-True ($runner.Records.Count -eq 0 -and $runner.Ledger.Count -eq 0) (
        'Peeking the manual gate must perform zero writes and zero effects.'
    )

    $prefixCount = 0
    while ($null -ne (Peek-FakeAction -Runner $runner)) {
        [void](Execute-FakeAction -Runner $runner)
        $prefixCount++
        $reopened = Copy-FakeRunner -Runner $runner
        Resume-FakeRunner -Runner $reopened
        $resumedDocument = New-OperationLog -Runner $reopened
        $resumedPath = Save-Document -Document $resumedDocument `
            -Name "resumed-prefix-$prefixCount"
        $resumed = Invoke-Evaluator -OperationLogPath $resumedPath `
            -HostManifestPath $hostManifestPath -VerifyCurrentWorkspace
        Assert-True ($resumed.ExitCode -eq 0) (
            "Recovered prefix $prefixCount must validate: " +
            "$($resumed.Output) $($resumed.ErrorOutput)"
        )
        Assert-True $resumed.Result.safe_to_resume (
            "Recovered prefix $prefixCount must pass the composite resume gate."
        )
        $recordsBeforeSecondResume = @($reopened.Records) |
            ConvertTo-Json -Depth 40 -Compress
        $ledgerBeforeSecondResume = $reopened.Ledger |
            ConvertTo-Json -Depth 10 -Compress
        Resume-FakeRunner -Runner $reopened
        Assert-True (
            $recordsBeforeSecondResume -ceq (
                @($reopened.Records) | ConvertTo-Json -Depth 40 -Compress
            )
        ) "Recovery must be idempotent for prefix $prefixCount records."
        Assert-True (
            $ledgerBeforeSecondResume -ceq (
                $reopened.Ledger | ConvertTo-Json -Depth 10 -Compress
            )
        ) "Recovery must be idempotent for prefix $prefixCount effects."
        foreach ($effect in $effects) {
            Assert-True ($reopened.Ledger[$effect.id] -eq 1) (
                "$($effect.id) must apply exactly once for prefix $prefixCount."
            )
        }
    }
    Assert-True ($prefixCount -eq 10) 'Every manual gate action must be covered.'

    $completeDocument = New-OperationLog -Runner $runner
    $completePath = Save-Document -Document $completeDocument -Name 'complete'
    $operationHashBefore = (Get-FileHash -LiteralPath $completePath).Hash
    $manifestHashBefore = (Get-FileHash -LiteralPath $hostManifestPath).Hash
    $valid = Invoke-Evaluator -OperationLogPath $completePath `
        -HostManifestPath $hostManifestPath -VerifyCurrentWorkspace
    Assert-True ($valid.ExitCode -eq 0) 'Complete operation evidence must validate.'
    Assert-True $valid.Result.passed 'Complete operation contract must pass.'
    Assert-True ($valid.Result.derived_state -ceq 'open') (
        'Complete recovery evidence must leave the operation open for resume.'
    )
    Assert-True $valid.Result.safe_to_resume (
        'Complete operation and checkpoint evidence must be safe to resume.'
    )
    Assert-True (
        $operationHashBefore -ceq (Get-FileHash -LiteralPath $completePath).Hash -and
        $manifestHashBefore -ceq (Get-FileHash -LiteralPath $hostManifestPath).Hash
    ) 'Evaluation must not mutate its durable inputs.'

    $historicalOnly = Invoke-Evaluator -OperationLogPath $completePath `
        -HostManifestPath $hostManifestPath
    Assert-True ($historicalOnly.ExitCode -eq 0) (
        'Historical evidence without current workspace verification remains valid.'
    )
    Assert-True (-not $historicalOnly.Result.safe_to_resume) (
        'Historical evidence must not authorize current resume.'
    )

    $pendingRunner = New-FakeRunner
    Add-StartRecord -Runner $pendingRunner
    Add-IntentRecord -Runner $pendingRunner -Effect $effects[0]
    $pendingDocument = New-OperationLog -Runner $pendingRunner
    $pendingDocument.runner_state.status = 'requires-reconciliation'
    $pendingPath = Save-Document -Document $pendingDocument `
        -Name 'current-replay-removed'
    $replayRemoved = Invoke-Evaluator -OperationLogPath $pendingPath `
        -HostManifestPath $hostManifestPath -SafeKinds @() `
        -VerifyCurrentWorkspace
    Assert-True ($replayRemoved.ExitCode -eq 0) (
        'A removed current replay declaration is valid evidence.'
    )
    Assert-True (
        $replayRemoved.Result.derived_state -ceq 'requires-reconciliation' -and
        -not $replayRemoved.Result.safe_to_resume
    ) 'Both persisted and current replay declarations must be safe.'

    $unsupportedCurrentPolicy = Invoke-Evaluator `
        -OperationLogPath $pendingPath -HostManifestPath $hostManifestPath `
        -SafeKinds @('tool') -VerifyCurrentWorkspace
    Assert-True ($unsupportedCurrentPolicy.ExitCode -ne 0) (
        'The first slice must not promote generic tool effects to replay-safe.'
    )

    $manualManifest = Get-Content -Raw -LiteralPath $hostManifestPath |
        ConvertFrom-Json
    $manualManifest.evidence_kind = 'manual-authorized-import'
    $manualManifest.model.version_evidence = 'user-supplied'
    $manualManifest.provenance.authorization = 'explicit-current-task'
    $manualManifest.provenance.model_execution_attested = $true
    $manualManifestPath = Save-Document -Document $manualManifest `
        -Name 'manual-host-manifest'
    $manualOperation = Copy-JsonValue -Value $completeDocument
    $manualOperation.records[0].authorization = 'explicit-current-task'
    foreach ($intent in @(
        $manualOperation.records | Where-Object type -CEQ 'effect-intended'
    )) {
        $intent.authorization_basis = 'explicit-current-task'
    }
    foreach ($effectResult in @(
        $manualOperation.records | Where-Object type -CEQ 'effect-result'
    )) {
        $effectResult.authorization_evidence = 'explicit-current-task'
    }
    $manualOperationPath = Save-Document -Document $manualOperation `
        -Name 'manual-operation-log'
    $manualResult = Invoke-Evaluator -OperationLogPath $manualOperationPath `
        -HostManifestPath $manualManifestPath -VerifyCurrentWorkspace
    Assert-True ($manualResult.ExitCode -eq 0) (
        'Manual operation evidence remains structurally valid.'
    )
    Assert-True (
        $manualResult.Result.durability_coverage -ceq 'unverified-live' -and
        -not $manualResult.Result.safe_to_resume
    ) 'Manual import must not claim pre-effect durable-operation coverage.'

    $mutations = @(
        [pscustomobject]@{
            name = 'sequence-gap'
            change = { param($doc) $doc.records[1].sequence = 3 }
        }
        [pscustomobject]@{
            name = 'duplicate-record-id'
            change = { param($doc) $doc.records[1].record_id = 'record-1' }
        }
        [pscustomobject]@{
            name = 'runner-state-mismatch'
            change = { param($doc) $doc.runner_state.status = 'completed' }
        }
        [pscustomobject]@{
            name = 'unauthorized-success'
            change = { param($doc) $doc.records[1].authorized = $false }
        }
        [pscustomobject]@{
            name = 'external-safe-replay'
            change = { param($doc) $doc.records[1].external = $true }
        }
        [pscustomobject]@{
            name = 'raw-arguments'
            change = {
                param($doc)
                $doc.records[1] | Add-Member -NotePropertyName arguments `
                    -NotePropertyValue 'not-allowed'
            }
        }
        [pscustomobject]@{
            name = 'host-link-mismatch'
            change = { param($doc) $doc.task_ref = 'another-task' }
        }
    )
    foreach ($mutation in $mutations) {
        $path = Save-Mutation -Base $completeDocument `
            -Mutation $mutation.change -Name $mutation.name
        $result = Invoke-Evaluator -OperationLogPath $path `
            -HostManifestPath $hostManifestPath -VerifyCurrentWorkspace
        Assert-True ($result.ExitCode -ne 0) (
            "$($mutation.name) must fail validation."
        )
    }

    $contradictoryEvidence = Copy-JsonValue -Value $completeDocument
    $contradictoryIntent = @(
        $contradictoryEvidence.records |
            Where-Object type -CEQ 'effect-intended'
    )[-1]
    $contradictoryResultRecord = @(
        $contradictoryEvidence.records |
            Where-Object type -CEQ 'effect-result'
    )[-1]
    $contradictoryIntent.authorized = $false
    $contradictoryIntent.authorization_basis = (
        'host-policy-pending'
    )
    $contradictoryResultRecord.result = 'failed'
    $contradictoryResultRecord.authorization_evidence = (
        'contract-fixture'
    )
    $contradictoryEvidence.runner_state.status = 'requires-reconciliation'
    $contradictoryEvidence.runner_state.pending_effect_id = (
        $contradictoryIntent.effect_id
    )
    $contradictoryPath = Save-Document -Document $contradictoryEvidence `
        -Name 'contradictory-authorization-evidence'
    $contradictoryResult = Invoke-Evaluator `
        -OperationLogPath $contradictoryPath `
        -HostManifestPath $hostManifestPath -VerifyCurrentWorkspace
    Assert-True ($contradictoryResult.ExitCode -ne 0) (
        'Verified result evidence must not contradict an unauthorized intent.'
    )

    $orphan = Copy-JsonValue -Value $completeDocument
    $orphan.records = @($orphan.records | Where-Object {
        -not ($_.type -ceq 'effect-intended' -and $_.effect_id -ceq 'checkpoint-effect')
    })
    for ($index = 0; $index -lt $orphan.records.Count; $index++) {
        $orphan.records[$index].sequence = $index + 1
        $orphan.records[$index].record_id = "record-$($index + 1)"
        $orphan.records[$index].previous_record_id = if ($index -eq 0) {
            $null
        } else { "record-$index" }
    }
    $orphan.runner_state.last_sequence = $orphan.records.Count
    $orphanPath = Save-Document -Document $orphan -Name 'orphan-result'
    $orphanResult = Invoke-Evaluator -OperationLogPath $orphanPath `
        -HostManifestPath $hostManifestPath -VerifyCurrentWorkspace
    Assert-True ($orphanResult.ExitCode -ne 0) (
        'An effect result without its intent must fail.'
    )

    $finishedRunner = Copy-FakeRunner -Runner $runner
    $finishSequence = Get-NextSequence -Runner $finishedRunner
    $finishPrevious = $finishedRunner.Records[$finishedRunner.Records.Count - 1]
    [void]$finishedRunner.Records.Add([pscustomobject][ordered]@{
        record_id = "record-$finishSequence"
        sequence = $finishSequence
        previous_record_id = $finishPrevious.record_id
        occurred_at = Get-RecordTime -Sequence $finishSequence
        operation_id = $operationId
        type = 'operation-finished'
        outcome = 'completed'
    })
    $finished = New-OperationLog -Runner $finishedRunner
    $finished | Add-Member -NotePropertyName completed_at `
        -NotePropertyValue (Get-RecordTime -Sequence $finishSequence)
    $finished.runner_state.status = 'completed'
    $finishedPath = Save-Document -Document $finished -Name 'finished'
    $finishedResult = Invoke-Evaluator -OperationLogPath $finishedPath `
        -HostManifestPath $hostManifestPath -VerifyCurrentWorkspace
    Assert-True ($finishedResult.ExitCode -eq 0) (
        'A completed operation is valid durable evidence.'
    )
    Assert-True (-not $finishedResult.Result.safe_to_resume) (
        'A completed operation must not offer resume.'
    )

    "[PASS] manual gate: $prefixCount action prefixes recovered twice"
    '[PASS] operation reducer: replay, fixed-point, and terminal states'
    '[PASS] composite gate: operation, checkpoint, workspace, and smoke evidence'
    '[PASS] negative contracts: structure, authorization, privacy, and host binding'
} finally {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    if (
        (Test-Path -LiteralPath $resolvedTempRoot) -and
        $resolvedTempRoot.StartsWith(
            $tempBase, [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Split-Path $resolvedTempRoot -Leaf) -like 'governance-operation-log-*'
    ) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
