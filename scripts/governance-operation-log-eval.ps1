[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OperationLogPath,
    [string]$SchemaPath,
    [string]$HostManifestPath,
    [string]$HostSchemaPath,
    [string]$CheckpointSchemaPath,
    [string]$CatalogSchemaPath,
    [string]$TrialsSchemaPath,
    [string]$CurrentSafeEffectKinds = '',
    [switch]$VerifyCurrentWorkspace,
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force
if ([string]::IsNullOrWhiteSpace($OperationLogPath)) {
    throw 'OperationLogPath is required.'
}
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $root (
        'evals\schemas\governance-operation-logs.schema.json'
    )
}
if ([string]::IsNullOrWhiteSpace($HostSchemaPath)) {
    $HostSchemaPath = Join-Path $root (
        'evals\schemas\governance-host-trials.schema.json'
    )
}
if ([string]::IsNullOrWhiteSpace($CheckpointSchemaPath)) {
    $CheckpointSchemaPath = Join-Path $root (
        'evals\schemas\governance-task-checkpoints.schema.json'
    )
}
if ([string]::IsNullOrWhiteSpace($CatalogSchemaPath)) {
    $CatalogSchemaPath = Join-Path $root (
        'evals\schemas\governance-behavior-cases.schema.json'
    )
}
if ([string]::IsNullOrWhiteSpace($TrialsSchemaPath)) {
    $TrialsSchemaPath = Join-Path $root (
        'evals\schemas\governance-behavior-trials.schema.json'
    )
}
$hostValidator = Join-Path $PSScriptRoot 'governance-host-trial-eval.ps1'
$requiredRecoveryEffects = @(
    'checkpoint-write',
    'smoke-test',
    'final-state-observation'
)
$allowedCurrentSafeEffectKinds = @(
    'checkpoint-write',
    'smoke-test',
    'final-state-observation'
)

function Test-HasProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)
    return $null -ne $Value -and $Value.PSObject.Properties.Name -contains $Name
}

$errors = [Collections.Generic.List[string]]::new()
$document = $null
$operationLogFullPath = $null
try {
    $operationLogFullPath = Resolve-RepositoryPath `
        -Root $root -Path $OperationLogPath -Label 'OperationLogPath' `
        -MaximumBytes 10MB
    $operationJson = Get-Content -Raw -LiteralPath $operationLogFullPath
    if (-not (
        Test-Json -Json $operationJson -SchemaFile $SchemaPath `
            -ErrorAction Stop
    )) {
        throw 'Operation log does not conform to its JSON Schema.'
    }
    $document = $operationJson | ConvertFrom-Json
    foreach ($path in @(Find-SensitiveValue $document)) {
        $errors.Add("Operation log contains a secret-like value at: $path")
    }
} catch {
    $errors.Add("Operation log validation failed: $($_.Exception.Message)")
}

$derivedState = 'requires-reconciliation'
$derivedPendingEffectId = $null
$operationId = $null
$lastSequence = 0
$operationResumable = $false
$authorizationVerified = $false
$requiredRecoveryEffectsPassed = $false
$recordIds = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
)
$intents = [Collections.Generic.Dictionary[string,object]]::new(
    [StringComparer]::Ordinal
)
$results = [Collections.Generic.Dictionary[string,object]]::new(
    [StringComparer]::Ordinal
)
$currentSafeKinds = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
)
foreach ($kind in @(
    $CurrentSafeEffectKinds -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)) {
    if ($kind -cnotin $allowedCurrentSafeEffectKinds) {
        throw "Unsupported CurrentSafeEffectKinds value: $kind"
    }
    [void]$currentSafeKinds.Add($kind)
}
$pendingIntent = $null
$unresolvedEffectId = $null
$finishRecord = $null
$documentStarted = $null
$documentCompleted = $null
$lastOccurred = $null
$startAuthorization = $null
$verifiedIntentCount = 0
$intentCount = 0

if ($null -ne $document) {
    try {
        $documentStarted = [DateTimeOffset]$document.started_at
        if (Test-HasProperty $document 'completed_at') {
            $documentCompleted = [DateTimeOffset]$document.completed_at
            if ($documentCompleted -lt $documentStarted) {
                $errors.Add('completed_at must not precede started_at.')
            }
        }
        $records = @($document.records)
        for ($index = 0; $index -lt $records.Count; $index++) {
            $record = $records[$index]
            $expectedSequence = $index + 1
            $lastSequence = [int]$record.sequence
            if ($lastSequence -ne $expectedSequence) {
                $errors.Add('Record sequence must be contiguous from one.')
            }
            $recordId = [string]$record.record_id
            if (-not $recordIds.Add($recordId)) {
                $errors.Add("Duplicate record_id: $recordId")
            }
            if ($index -eq 0) {
                if ($null -ne $record.previous_record_id) {
                    $errors.Add('The first record must have null previous_record_id.')
                }
            } elseif (
                [string]$record.previous_record_id -cne
                    [string]$records[$index - 1].record_id
            ) {
                $errors.Add("Record chain is broken at $recordId.")
            }
            $occurred = [DateTimeOffset]$record.occurred_at
            if ($occurred -lt $documentStarted) {
                $errors.Add("$recordId occurred before the operation log started.")
            }
            if ($null -ne $documentCompleted -and $occurred -gt $documentCompleted) {
                $errors.Add("$recordId occurred after completed_at.")
            }
            if ($null -ne $lastOccurred -and $occurred -lt $lastOccurred) {
                $errors.Add('Record timestamps must be monotonic.')
            }
            $lastOccurred = $occurred
            if ($null -ne $finishRecord) {
                $errors.Add('No record may follow operation-finished.')
            }

            switch ([string]$record.type) {
                'operation-started' {
                    if ($index -ne 0 -or $null -ne $operationId) {
                        $errors.Add('Exactly one first operation-started record is required.')
                    }
                    $operationId = [string]$record.operation_id
                    $startAuthorization = [string]$record.authorization
                }
                'effect-intended' {
                    if ($null -eq $operationId) {
                        $errors.Add("$recordId appears before operation-started.")
                    }
                    if ($null -ne $pendingIntent) {
                        $errors.Add(
                            "$recordId starts an effect before the prior effect has a result."
                        )
                    }
                    if ($null -ne $unresolvedEffectId) {
                        $errors.Add(
                            "$recordId starts new work after an unresolved effect."
                        )
                    }
                    $effectId = [string]$record.effect_id
                    if ($intents.ContainsKey($effectId)) {
                        $errors.Add("Duplicate effect intent: $effectId")
                    } else {
                        $intents.Add($effectId, $record)
                    }
                    $intentCount++
                    $basis = [string]$record.authorization_basis
                    if ([bool]$record.authorized) {
                        if ($basis -cnotin @(
                            'contract-fixture', 'explicit-current-task'
                        )) {
                            $errors.Add(
                                "$effectId claims authorization without verified basis."
                            )
                        } elseif ($basis -cne $startAuthorization) {
                            $errors.Add(
                                "$effectId authorization basis does not match the operation."
                            )
                        } else {
                            $verifiedIntentCount++
                        }
                    } elseif ($basis -cin @(
                        'contract-fixture', 'explicit-current-task'
                    )) {
                        $errors.Add(
                            "$effectId denies authorization despite verified basis."
                        )
                    }
                    if (
                        [string]$record.replay -ceq 'safe' -and (
                            [bool]$record.external -or [bool]$record.destructive
                        )
                    ) {
                        $errors.Add(
                            "$effectId cannot declare safe replay when external or destructive."
                        )
                    }
                    $pendingIntent = $record
                }
                'effect-result' {
                    $effectId = [string]$record.effect_id
                    if (-not $intents.ContainsKey($effectId)) {
                        $errors.Add("$effectId has a result without an intent.")
                    }
                    if ($results.ContainsKey($effectId)) {
                        $errors.Add("Duplicate effect result: $effectId")
                    } else {
                        $results.Add($effectId, $record)
                    }
                    if (
                        $null -eq $pendingIntent -or
                        [string]$pendingIntent.effect_id -cne $effectId
                    ) {
                        $errors.Add("$effectId result does not close the pending effect.")
                    } else {
                        $authorizationEvidence = [string](
                            $record.authorization_evidence
                        )
                        if (
                            [bool]$pendingIntent.authorized -and
                            $authorizationEvidence -cne
                                [string]$pendingIntent.authorization_basis
                        ) {
                            $errors.Add(
                                "$effectId result authorization evidence does not match its intent."
                            )
                        } elseif (
                            -not [bool]$pendingIntent.authorized -and
                            $authorizationEvidence -cin @(
                                'contract-fixture', 'explicit-current-task'
                            )
                        ) {
                            $errors.Add(
                                "$effectId result evidence contradicts its unauthorized intent."
                            )
                        } elseif (
                            [string]$record.result -ceq 'succeeded' -and
                            -not [bool]$pendingIntent.authorized -and
                            $authorizationEvidence -cne 'host-permitted'
                        ) {
                            $errors.Add(
                                "$effectId records success without task or host authorization evidence."
                            )
                        }
                        if ([string]$record.result -cne 'succeeded') {
                            $unresolvedEffectId = $effectId
                        }
                        $pendingIntent = $null
                    }
                }
                'operation-finished' {
                    if ($null -ne $pendingIntent) {
                        $errors.Add('operation-finished cannot close a pending effect.')
                    }
                    $finishRecord = $record
                }
                default {
                    $errors.Add("Unknown operation record type: $($record.type)")
                }
            }
            if (
                $null -ne $operationId -and
                [string]$record.operation_id -cne $operationId
            ) {
                $errors.Add("$recordId does not belong to $operationId.")
            }
        }

        if ($null -eq $operationId) {
            $errors.Add('Operation log has no operation-started record.')
        }
        if ($null -ne $finishRecord -and $null -eq $documentCompleted) {
            $errors.Add('A finished operation requires completed_at.')
        }
        if ($null -eq $finishRecord -and $null -ne $documentCompleted) {
            $errors.Add('completed_at requires operation-finished.')
        }
        if (
            $null -ne $finishRecord -and
            [string]$finishRecord.outcome -ceq 'completed' -and
            $null -ne $unresolvedEffectId
        ) {
            $errors.Add('A completed operation cannot contain an unresolved effect.')
        }

        if ($null -ne $finishRecord) {
            $derivedState = [string]$finishRecord.outcome
            $derivedPendingEffectId = $null
        } elseif ($null -ne $pendingIntent) {
            $derivedPendingEffectId = [string]$pendingIntent.effect_id
            $canReplay = (
                [string]$pendingIntent.replay -ceq 'safe' -and
                -not [bool]$pendingIntent.external -and
                -not [bool]$pendingIntent.destructive -and
                $currentSafeKinds.Contains([string]$pendingIntent.effect_kind)
            )
            $derivedState = if ($canReplay) {
                'replayable'
            } else { 'requires-reconciliation' }
        } elseif ($null -ne $unresolvedEffectId) {
            $derivedState = 'requires-reconciliation'
            $derivedPendingEffectId = $unresolvedEffectId
        } else {
            $derivedState = 'open'
            $derivedPendingEffectId = $null
        }

        $runnerState = $document.runner_state
        if ([string]$runnerState.status -cne $derivedState) {
            $errors.Add('runner_state.status does not match the reduced state.')
        }
        $recordedPending = if ($null -eq $runnerState.pending_effect_id) {
            $null
        } else { [string]$runnerState.pending_effect_id }
        if ($recordedPending -cne $derivedPendingEffectId) {
            $errors.Add('runner_state.pending_effect_id does not match the reduced state.')
        }
        if ([int]$runnerState.last_sequence -ne $lastSequence) {
            $errors.Add('runner_state.last_sequence does not match the durable log.')
        }

        $requiredRecoveryEffectsPassed = $true
        foreach ($effectKind in $requiredRecoveryEffects) {
            $matchingEffectIds = @(
                $intents.GetEnumerator() |
                    Where-Object { [string]$_.Value.effect_kind -ceq $effectKind } |
                    ForEach-Object Key
            )
            $kindPassed = @(
                $matchingEffectIds | Where-Object {
                    $results.ContainsKey($_) -and
                    [string]$results[$_].result -ceq 'succeeded'
                }
            ).Count -eq 1
            if (-not $kindPassed) { $requiredRecoveryEffectsPassed = $false }
        }
        $operationResumable = $derivedState -in @('open', 'replayable')
        $authorizationVerified = (
            $startAuthorization -cin @(
                'contract-fixture', 'explicit-current-task'
            ) -and
            $intentCount -gt 0 -and
            $verifiedIntentCount -eq $intentCount
        )
    } catch {
        $errors.Add("Operation reduction failed: $($_.Exception.Message)")
    }
}

$checkpointGateEvaluated = $false
$checkpointGatePassed = $false
$durabilityCoverage = 'not-evaluated'
if (
    $null -ne $document -and
    $startAuthorization -ceq 'host-hook-policy'
) {
    $durabilityCoverage = 'host-hook-unverified'
}
if (-not [string]::IsNullOrWhiteSpace($HostManifestPath)) {
    try {
        $hostManifestFullPath = Resolve-RepositoryPath `
            -Root $root -Path $HostManifestPath -Label 'HostManifestPath' `
            -MaximumBytes 10MB
        $validationParameters = @{
            ProjectRoot = $root
            ManifestPath = $hostManifestFullPath
            SchemaPath = $HostSchemaPath
            CheckpointSchemaPath = $CheckpointSchemaPath
            CatalogSchemaPath = $CatalogSchemaPath
            TrialsSchemaPath = $TrialsSchemaPath
            VerifyCurrentWorkspace = $VerifyCurrentWorkspace
            Json = $true
            NoExit = $true
        }
        $validationOutput = @(& $hostValidator @validationParameters)
        $checkpointGateEvaluated = $true
        $hostResult = $null
        try {
            $hostResult = ($validationOutput -join "`n") | ConvertFrom-Json
        } catch {
            $details = ($validationOutput -join ' | ').Trim()
            throw "Host checkpoint validator returned invalid JSON: $details"
        }
        if (-not [bool]$hostResult.passed) {
            foreach ($message in @($hostResult.errors)) {
                $errors.Add("Host checkpoint gate: $message")
            }
        } else {
            $checkpointGatePassed = [bool]$hostResult.safe_to_resume
        }

        if ($null -ne $document) {
            $hostManifest = Get-Content -Raw -LiteralPath $hostManifestFullPath |
                ConvertFrom-Json
            $durabilityCoverage = if (
                [string]$hostManifest.evidence_kind -ceq 'contract-fixture'
            ) {
                'contract-fixture'
            } else { 'unverified-live' }
            $expectedAuthorization = if (
                $durabilityCoverage -ceq 'contract-fixture'
            ) {
                'contract-fixture'
            } else { 'explicit-current-task' }
            $startAuthorization = @(
                $document.records |
                    Where-Object type -CEQ 'operation-started' |
                    ForEach-Object authorization
            )
            if (
                $startAuthorization.Count -ne 1 -or
                [string]$startAuthorization[0] -cne $expectedAuthorization
            ) {
                $errors.Add(
                    'Operation authorization does not match the host evidence kind.'
                )
            }
            if ([string]$document.host_run_id -cne [string]$hostManifest.run_id) {
                $errors.Add('host_run_id does not match the host manifest.')
            }
            if (
                [string]$document.task_ref -cne
                    [string]$hostManifest.checkpoint.task_ref
            ) {
                $errors.Add('task_ref does not match the host checkpoint.')
            }
            if (
                [string]$document.case_id -cnotin
                    @($hostManifest.checkpoint.case_ids)
            ) {
                $errors.Add('case_id is not covered by the host checkpoint.')
            }
            $hostStarted = [DateTimeOffset]$hostManifest.started_at
            $hostCompleted = [DateTimeOffset]$hostManifest.completed_at
            if (
                $documentStarted -lt $hostStarted -or
                $lastOccurred -gt $hostCompleted
            ) {
                $errors.Add('Operation log timestamps fall outside the host trial.')
            }
        }
    } catch {
        $errors.Add("Host checkpoint validation failed: $($_.Exception.Message)")
    }
}

$passed = $errors.Count -eq 0
$safeToResume = (
    $passed -and
    $durabilityCoverage -ceq 'contract-fixture' -and
    $authorizationVerified -and
    $operationResumable -and
    $requiredRecoveryEffectsPassed -and
    $checkpointGatePassed
)
$result = [pscustomobject]@{
    passed = $passed
    log_id = if ($null -eq $document) { $null } else { $document.log_id }
    operation_id = $operationId
    derived_state = $derivedState
    pending_effect_id = $derivedPendingEffectId
    last_sequence = $lastSequence
    operation_resumable = $operationResumable
    required_recovery_effects_passed = $requiredRecoveryEffectsPassed
    checkpoint_gate_evaluated = $checkpointGateEvaluated
    checkpoint_gate_passed = $checkpointGatePassed
    durability_coverage = $durabilityCoverage
    authorization_verified = $authorizationVerified
    safe_to_resume = $safeToResume
    errors = @($errors)
}
if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    if ($errors.Count) {
        foreach ($message in $errors) { "[FAIL] $message" }
    } else {
        "[PASS] operation-log: state=$derivedState; sequence=$lastSequence"
        "[PASS] recovery-effects: complete=$requiredRecoveryEffectsPassed"
        "[PASS] checkpoint-gate: safe_to_resume=$safeToResume"
    }
    "Summary: $(if ($passed) { 'passed' } else { 'failed' })."
}
if (-not $passed -and -not $NoExit) { exit 1 }
