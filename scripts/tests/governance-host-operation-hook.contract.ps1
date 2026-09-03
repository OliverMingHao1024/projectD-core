[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$hook = Join-Path $core 'scripts\governance-host-operation-hook.ps1'
$evaluator = Join-Path $core 'scripts\governance-operation-log-eval.ps1'
$schema = Join-Path $core 'evals\schemas\governance-operation-logs.schema.json'
$runtimePolicySchema = Join-Path $core 'evals\schemas\governance-runtime-policy-decisions.schema.json'
$taskAuthorizationSchema = Join-Path $core 'evals\schemas\governance-task-authorizations.schema.json'
$codexConfig = Join-Path $core '.codex\hooks.json'
$codexWindowsLauncher = Join-Path $core 'scripts\codex-governance-hook.cmd'
$claudeConfig = Join-Path $core '.claude\settings.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "governance-host-operation-hook-$PID"
)
Import-Module (Join-Path $core 'scripts\lib\GovernanceCommon.psm1') -Force
Import-Module (Join-Path $core 'scripts\lib\RuntimePolicy.psm1') -Force
$runtimePolicyDigest = Get-ProjectDRuntimePolicyDigest -ProjectRoot $core

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Copy-JsonValue {
    param([Parameter(Mandatory)]$Value)
    return $Value | ConvertTo-Json -Depth 64 | ConvertFrom-Json
}

function Invoke-ScriptProcess {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$StandardInput = ''
    )
    $pwsh = Get-Command pwsh -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $ScriptPath) + $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($startInfo)
    $process.StandardInput.Write($StandardInput)
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(15000)
    if ($timedOut) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    [pscustomobject]@{
        ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        Stdout = $stdoutTask.GetAwaiter().GetResult()
        Stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

function Invoke-HostHook {
    param(
        [Parameter(Mandatory)][ValidateSet('codex', 'claude')][string]$HostName,
        [Parameter(Mandatory)]$Payload
    )
    $arguments = @(
        '-HostName', $HostName,
        '-ProjectRoot', $tempRoot,
        '-SchemaPath', $schema,
        '-RuntimePolicySchemaPath', $runtimePolicySchema,
        '-TaskAuthorizationSchemaPath', $taskAuthorizationSchema,
        '-ExpectedEventName', ([string]$Payload.hook_event_name),
        '-AllowContractAuthorizationFixture'
    )
    return Invoke-ScriptProcess -ScriptPath $hook -Arguments $arguments `
        -StandardInput ($Payload | ConvertTo-Json -Depth 64 -Compress)
}

function Get-HostLogs {
    param([Parameter(Mandatory)][string]$HostName)
    $directory = Join-Path $tempRoot (
        ".local\governance\operation-hooks\$HostName"
    )
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -Recurse
    )
}

function Get-HostPolicyDecisions {
    param([Parameter(Mandatory)][string]$HostName)
    $directory = Join-Path $tempRoot (
        ".local\governance\runtime-policy\$HostName"
    )
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -Recurse
    )
}

function Write-TaskAuthorizationFixture {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$Capability,
        [Parameter(Mandatory)][string]$TargetClass,
        [bool]$AllowExternal = $false,
        [bool]$AllowDestructive = $false
    )
    $sessionIdentity = "$HostName`0$SessionId"
    $digest = Get-TextSha256 -Text $sessionIdentity
    $sessionSlug = "session-$($digest.Substring(7, 32))"
    $taskRef = "host-hook-$sessionSlug"
    $hostRunId = "$HostName-$sessionSlug"
    $directory = Join-Path $tempRoot (
        ".local\governance\task-authorizations\$HostName"
    )
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $document = [ordered]@{
        schema_version = 1
        authorization_id = "authorization-$($digest.Substring(7, 16))"
        source_decision_id = "decision-contract-$($digest.Substring(7, 16))"
        task_ref = $taskRef
        host_run_id = $hostRunId
        issued_at = [DateTimeOffset]::UtcNow.ToString('o')
        expires_at = [DateTimeOffset]::UtcNow.AddMinutes(10).ToString('o')
        policy = [ordered]@{
            policy_id = 'runtime-governance-v2'
            policy_version = 1
            policy_digest = $runtimePolicyDigest
        }
        authorization = [ordered]@{
            basis = 'explicit-current-task'
            scope_match = 'exact'
            authorized_by = 'contract-fixture'
        }
        grants = @(
            [ordered]@{
                capability = $Capability
                target_class = $TargetClass
                allow_external = $AllowExternal
                allow_destructive = $AllowDestructive
            }
        )
        privacy = [ordered]@{
            content_mode = 'metadata-only'
            contains_raw_prompt = $false
            contains_chain_of_thought = $false
            contains_secret_values = $false
            contains_tool_arguments = $false
            contains_tool_output = $false
        }
    }
    $path = Join-Path $directory "$taskRef.json"
    $document | ConvertTo-Json -Depth 32 |
        Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
    return $path
}

function New-HookPayload {
    param(
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$ToolUseId,
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)]$ToolInput,
        $ToolResponse,
        [string]$ErrorText
    )
    $payload = [ordered]@{
        session_id = $SessionId
        turn_id = 'turn-contract'
        cwd = $tempRoot
        permission_mode = 'default'
        hook_event_name = $Event
        tool_name = $ToolName
        tool_use_id = $ToolUseId
        tool_input = $ToolInput
    }
    if ($PSBoundParameters.ContainsKey('ToolResponse')) {
        $payload.tool_response = $ToolResponse
    }
    if ($PSBoundParameters.ContainsKey('ErrorText')) {
        $payload.error = $ErrorText
    }
    return [pscustomobject]$payload
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Assert-True (Test-Path -LiteralPath $hook -PathType Leaf) (
        'The provider-neutral host operation hook must exist.'
    )
    Assert-True (Test-Path -LiteralPath $codexConfig -PathType Leaf) (
        'Codex repository hook configuration must exist.'
    )
    Assert-True (Test-Path -LiteralPath $codexWindowsLauncher -PathType Leaf) (
        'Codex Windows hooks must use the quote-free launcher.'
    )
    Assert-True (Test-Path -LiteralPath $claudeConfig -PathType Leaf) (
        'Claude repository hook configuration must exist.'
    )

    $secretMarker = 'raw-api-key-must-never-be-persisted'
    $codexInput = [pscustomobject][ordered]@{
        file_path = "fixture-$secretMarker.txt"
        nested = [pscustomobject]@{ password = $secretMarker }
    }
    $codexPre = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-one' `
        -ToolName 'Read' `
        -ToolInput $codexInput
    $preResult = Invoke-HostHook -HostName codex -Payload $codexPre
    Assert-True ($preResult.ExitCode -eq 0) (
        "Codex PreToolUse must persist before allowing: $($preResult.Stderr)"
    )
    Assert-True ([string]::IsNullOrWhiteSpace($preResult.Stdout)) (
        'A successful PreToolUse hook must not bypass the host permission flow.'
    )
    $codexLogs = Get-HostLogs -HostName codex
    Assert-True ($codexLogs.Count -eq 1) 'Codex PreToolUse must create one log.'
    $preText = Get-Content -Raw -LiteralPath $codexLogs[0].FullName
    Assert-True (-not $preText.Contains($secretMarker)) (
        'Raw tool input and secret-like values must never be persisted.'
    )
    $preDocument = $preText | ConvertFrom-Json
    $codexPolicy = Get-HostPolicyDecisions -HostName codex
    Assert-True ($codexPolicy.Count -eq 1) (
        'Codex PreToolUse must create one runtime policy decision.'
    )
    $policyDocument = Get-Content -Raw -LiteralPath $codexPolicy[0].FullName |
        ConvertFrom-Json
    Assert-True (
        [string]$policyDocument.request.capability -ceq 'local-read' -and
        [string]$policyDocument.decision.outcome -ceq 'observe-only' -and
        [string]$policyDocument.authorization.state -ceq 'unavailable' -and
        [string]$policyDocument.coverage.enforcement -ceq 'advisory'
    ) (
        'A local read must remain observable without claiming task authorization.'
    )
    Assert-True (-not (
        Get-Content -Raw -LiteralPath $codexPolicy[0].FullName
    ).Contains($secretMarker)) (
        'Runtime policy evidence must not persist raw tool input.'
    )
    Assert-True (@($preDocument.records).Count -eq 2) (
        'PreToolUse must durably record operation start and effect intent.'
    )
    Assert-True (
        $preDocument.records[1].type -ceq 'effect-intended' -and
        $preDocument.records[1].authorization_basis -ceq 'host-policy-pending' -and
        -not [bool]$preDocument.records[1].authorized
    ) 'The live intent must not claim task authorization before host policy runs.'
    Assert-True (
        $preDocument.runner_state.status -ceq 'requires-reconciliation'
    ) 'A non-replayable pre-effect intent must require reconciliation.'

    $postPayload = New-HookPayload -Event 'PostToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-one' `
        -ToolName 'Read' `
        -ToolInput $codexInput `
        -ToolResponse ([pscustomobject]@{ success = $true })
    $postResult = Invoke-HostHook -HostName codex -Payload $postPayload
    Assert-True ($postResult.ExitCode -eq 0) (
        "Codex PostToolUse must close the intent: $($postResult.Stderr)"
    )
    $postDocument = Get-Content -Raw -LiteralPath $codexLogs[0].FullName |
        ConvertFrom-Json
    Assert-True (@($postDocument.records).Count -eq 3) (
        'PostToolUse must append exactly one result.'
    )
    Assert-True (
        $postDocument.records[2].result -ceq 'succeeded' -and
        $postDocument.records[2].authorization_evidence -ceq 'host-permitted'
    ) 'A completed host tool must record host permission without claiming task scope.'
    Assert-True ($postDocument.runner_state.status -ceq 'open') (
        'A closed live effect must reduce to open.'
    )

    $hashBeforeDuplicate = (Get-FileHash -LiteralPath $codexLogs[0].FullName).Hash
    $duplicatePost = Invoke-HostHook -HostName codex -Payload $postPayload
    Assert-True ($duplicatePost.ExitCode -eq 0) (
        'A duplicate identical PostToolUse must be idempotent.'
    )
    Assert-True (
        $hashBeforeDuplicate -ceq
            (Get-FileHash -LiteralPath $codexLogs[0].FullName).Hash
    ) 'Duplicate result delivery must not rewrite durable evidence.'

    $mismatchedPost = Copy-JsonValue -Value $postPayload
    $mismatchedPost.tool_input.file_path = 'different-file.txt'
    $mismatchResult = Invoke-HostHook -HostName codex -Payload $mismatchedPost
    Assert-True ($mismatchResult.ExitCode -eq 2) (
        'A result whose input digest differs from its intent must fail closed.'
    )
    Assert-True (
        $hashBeforeDuplicate -ceq
            (Get-FileHash -LiteralPath $codexLogs[0].FullName).Hash
    ) 'A rejected result must not mutate durable evidence.'

    $mismatchedTool = Copy-JsonValue -Value $postPayload
    $mismatchedTool.tool_name = 'Bash'
    $toolMismatchResult = Invoke-HostHook -HostName codex `
        -Payload $mismatchedTool
    Assert-True ($toolMismatchResult.ExitCode -eq 2) (
        'A result whose tool name differs from its intent must fail closed.'
    )
    Assert-True (
        $hashBeforeDuplicate -ceq
            (Get-FileHash -LiteralPath $codexLogs[0].FullName).Hash
    ) 'A rejected tool-name substitution must not mutate durable evidence.'

    $pathsBeforeAdditiveCase = @(
        Get-HostLogs -HostName codex | ForEach-Object FullName
    )
    $additiveInput = [pscustomobject][ordered]@{ questions = 'pick one' }
    $additivePre = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-additive' `
        -ToolName 'AskUserQuestion' `
        -ToolInput $additiveInput
    $additivePreResult = Invoke-HostHook -HostName codex -Payload $additivePre
    Assert-True ($additivePreResult.ExitCode -eq 0) (
        "The additive-key fixture must create a durable pre-effect intent: " +
            $additivePreResult.Stderr
    )
    $additiveLog = @(
        Get-HostLogs -HostName codex | Where-Object {
            $_.FullName -cnotin $pathsBeforeAdditiveCase
        }
    )
    Assert-True ($additiveLog.Count -eq 1) (
        'The additive-key fixture must identify exactly one new operation log.'
    )
    $additiveGrownInput = Copy-JsonValue -Value $additiveInput
    $additiveGrownInput | Add-Member -NotePropertyName 'answers' `
        -NotePropertyValue ([pscustomobject]@{ 'pick one' = 'A' })
    $additivePost = New-HookPayload -Event 'PostToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-additive' `
        -ToolName 'AskUserQuestion' `
        -ToolInput $additiveGrownInput `
        -ToolResponse ([pscustomobject]@{ success = $true })
    $additivePostResult = Invoke-HostHook -HostName codex -Payload $additivePost
    Assert-True ($additivePostResult.ExitCode -eq 0) (
        "A result that only adds new tool_input keys (e.g. an elicitation " +
            "tool's resolved answers) must not fail closed: " +
            $additivePostResult.Stderr
    )
    $additiveDocument = Get-Content -Raw -LiteralPath $additiveLog[0].FullName |
        ConvertFrom-Json
    Assert-True (
        @($additiveDocument.records).Count -eq 3 -and
        $additiveDocument.records[2].result -ceq 'succeeded' -and
        $additiveDocument.runner_state.status -ceq 'open'
    ) 'An additive-only result must close the intent normally.'

    $additiveTamperPre = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-additive-tamper' `
        -ToolName 'AskUserQuestion' `
        -ToolInput $additiveInput
    $additiveTamperPreResult = Invoke-HostHook -HostName codex `
        -Payload $additiveTamperPre
    Assert-True ($additiveTamperPreResult.ExitCode -eq 0) (
        'The additive-tamper fixture must create a durable pre-effect intent.'
    )
    $additiveTamperedPost = Copy-JsonValue -Value $additivePost
    $additiveTamperedPost.tool_use_id = 'codex-tool-call-additive-tamper'
    $additiveTamperedPost.tool_input.questions = 'a different question'
    $additiveTamperResult = Invoke-HostHook -HostName codex `
        -Payload $additiveTamperedPost
    Assert-True ($additiveTamperResult.ExitCode -eq 2) (
        'Changing a key that was already present at intent time must still ' +
            'fail closed even when other keys are additive.'
    )

    $pathsBeforeTamperCase = @(
        Get-HostLogs -HostName codex | ForEach-Object FullName
    )
    $tamperInput = [pscustomobject]@{ file_path = 'tamper-fixture.txt' }
    $tamperPre = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-tamper' `
        -ToolName 'Read' `
        -ToolInput $tamperInput
    $tamperPreResult = Invoke-HostHook -HostName codex -Payload $tamperPre
    Assert-True ($tamperPreResult.ExitCode -eq 0) (
        'The tamper fixture must create a durable pre-effect intent.'
    )
    $tamperedLog = @(
        Get-HostLogs -HostName codex | Where-Object {
            $_.FullName -cnotin $pathsBeforeTamperCase
        }
    )
    Assert-True ($tamperedLog.Count -eq 1) (
        'The tamper fixture must identify exactly one new operation log.'
    )
    $tamperedDocument = Get-Content -Raw -LiteralPath $tamperedLog[0].FullName |
        ConvertFrom-Json
    $tamperedDocument.records[0].operation_id = 'operation-tampered'
    $tamperedDocument | ConvertTo-Json -Depth 32 |
        Set-Content -LiteralPath $tamperedLog[0].FullName -Encoding utf8 `
            -NoNewline
    $tamperedHash = (Get-FileHash -LiteralPath $tamperedLog[0].FullName).Hash
    $tamperPost = New-HookPayload -Event 'PostToolUse' `
        -SessionId 'codex-session-contract' `
        -ToolUseId 'codex-tool-call-tamper' `
        -ToolName 'Read' `
        -ToolInput $tamperInput `
        -ToolResponse ([pscustomobject]@{ success = $true })
    $tamperPostResult = Invoke-HostHook -HostName codex -Payload $tamperPost
    Assert-True ($tamperPostResult.ExitCode -eq 2) (
        'A post event must fail closed when durable intent metadata was changed.'
    )
    Assert-True (
        $tamperedHash -ceq
            (Get-FileHash -LiteralPath $tamperedLog[0].FullName).Hash
    ) 'Rejected tampered evidence must not be rewritten.'

    $evaluation = Invoke-ScriptProcess -ScriptPath $evaluator -Arguments @(
        '-ProjectRoot', $tempRoot,
        '-OperationLogPath', $codexLogs[0].FullName,
        '-SchemaPath', $schema,
        '-Json'
    )
    $evaluationResult = $evaluation.Stdout | ConvertFrom-Json
    Assert-True ($evaluation.ExitCode -eq 0 -and $evaluationResult.passed) (
        'Host-hook evidence must remain structurally valid.'
    )
    Assert-True (
        $evaluationResult.durability_coverage -ceq 'host-hook-unverified' -and
        -not $evaluationResult.authorization_verified -and
        -not $evaluationResult.safe_to_resume
    ) 'Host-hook evidence must not overclaim task authorization or safe resume.'

    $logsBeforeNoEnvelopeWrite = @(Get-HostLogs -HostName codex).Count
    $noEnvelopeWrite = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'codex-session-no-envelope' `
        -ToolUseId 'codex-tool-call-no-envelope-write' `
        -ToolName 'apply_patch' `
        -ToolInput ([pscustomobject]@{
            command = "*** Begin Patch`n*** Add File: ordinary.txt`n+fixture`n*** End Patch"
        })
    $noEnvelopeWriteResult = Invoke-HostHook -HostName codex `
        -Payload $noEnvelopeWrite
    Assert-True ($noEnvelopeWriteResult.ExitCode -eq 0) (
        'Codex must return a structured deny rather than a hook failure.'
    )
    $noEnvelopeResponse = $noEnvelopeWriteResult.Stdout | ConvertFrom-Json
    Assert-True (
        $noEnvelopeResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $noEnvelopeResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'task-authorization-required'
        )
    ) 'An effectful request without an envelope must be denied before intent.'
    Assert-True (
        @(Get-HostLogs -HostName codex).Count -eq $logsBeforeNoEnvelopeWrite
    ) 'A denied no-envelope write must not create an operation intent.'
    $noEnvelopeCallDigest = Get-TextSha256 -Text (
        "codex`0codex-session-no-envelope`0codex-tool-call-no-envelope-write"
    )
    $noEnvelopePolicy = Get-Item -LiteralPath (Join-Path $tempRoot (
        '.local\governance\runtime-policy\codex\decision-call-' +
        $noEnvelopeCallDigest.Substring(7, 32) + '.json'
    ))
    $noEnvelopePolicyHash = (
        Get-FileHash -LiteralPath $noEnvelopePolicy.FullName
    ).Hash
    [void](Write-TaskAuthorizationFixture -HostName codex `
        -SessionId 'codex-session-no-envelope' `
        -Capability 'workspace-write' `
        -TargetClass 'workspace-file')
    $reusedDeniedCall = Invoke-HostHook -HostName codex `
        -Payload $noEnvelopeWrite
    $reusedDeniedResponse = $reusedDeniedCall.Stdout | ConvertFrom-Json
    Assert-True (
        $reusedDeniedCall.ExitCode -eq 0 -and
        $reusedDeniedResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $reusedDeniedResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'internal-error'
        )
    ) 'A denied tool-use identity must not become allowed after authorization changes.'
    Assert-True (
        $noEnvelopePolicyHash -ceq (
            Get-FileHash -LiteralPath $noEnvelopePolicy.FullName
        ).Hash
    ) 'A runtime policy decision must be immutable for one tool-use identity.'

    $invalidEnvelopeSession = 'codex-session-invalid-envelope'
    $invalidEnvelopePath = Write-TaskAuthorizationFixture -HostName codex `
        -SessionId $invalidEnvelopeSession `
        -Capability 'workspace-write' `
        -TargetClass 'workspace-file'
    '{}' | Set-Content -LiteralPath $invalidEnvelopePath -Encoding utf8 `
        -NoNewline
    $invalidEnvelopeWrite = New-HookPayload -Event 'PreToolUse' `
        -SessionId $invalidEnvelopeSession `
        -ToolUseId 'codex-tool-call-invalid-envelope' `
        -ToolName 'apply_patch' `
        -ToolInput ([pscustomobject]@{
            command = "*** Begin Patch`n*** Add File: invalid-envelope.txt`n+fixture`n*** End Patch"
        })
    $invalidEnvelopeResult = Invoke-HostHook -HostName codex `
        -Payload $invalidEnvelopeWrite
    $invalidEnvelopeResponse = $invalidEnvelopeResult.Stdout | ConvertFrom-Json
    Assert-True (
        $invalidEnvelopeResult.ExitCode -eq 0 -and
        $invalidEnvelopeResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $invalidEnvelopeResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'internal-error'
        )
    ) 'An invalid envelope must fail closed through Codex structured deny.'

    $enforcedSession = 'codex-session-enforced'
    [void](Write-TaskAuthorizationFixture -HostName codex `
        -SessionId $enforcedSession `
        -Capability 'workspace-write' `
        -TargetClass 'workspace-file')
    $enforcedWrite = New-HookPayload -Event 'PreToolUse' `
        -SessionId $enforcedSession `
        -ToolUseId 'codex-tool-call-enforced-write' `
        -ToolName 'apply_patch' `
        -ToolInput ([pscustomobject]@{
            command = "*** Begin Patch`n*** Add File: fixture.txt`n+fixture`n*** End Patch"
        })
    $enforcedWriteResult = Invoke-HostHook -HostName codex -Payload $enforcedWrite
    Assert-True ($enforcedWriteResult.ExitCode -eq 0) (
        'A task envelope grant must allow its matching workspace-write capability.'
    )
    $enforcedDecisions = @(Get-HostPolicyDecisions -HostName codex | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
    } | Where-Object {
        $_.request.capability -ceq 'workspace-write' -and
        $_.coverage.enforcement -ceq 'enforced' -and
        $_.authorization.state -ceq 'verified' -and
        $_.decision.outcome -ceq 'allow'
    })
    Assert-True ($enforcedDecisions.Count -ge 1) (
        'A matching task envelope must produce an enforced allow decision.'
    )
    Assert-True (
        $enforcedDecisions.Count -ge 1
    ) 'Enforced allow must carry verified task authorization.'

    $protectedControlWrite = New-HookPayload -Event 'PreToolUse' `
        -SessionId $enforcedSession `
        -ToolUseId 'codex-tool-call-protected-control' `
        -ToolName 'apply_patch' `
        -ToolInput ([pscustomobject]@{
            command = "*** Begin Patch`n*** Update File: scripts/lib/RuntimePolicy.psm1`n@@`n-old`n+tamper`n*** End Patch"
        })
    $protectedControlResult = Invoke-HostHook -HostName codex `
        -Payload $protectedControlWrite
    $protectedControlResponse = $protectedControlResult.Stdout | ConvertFrom-Json
    Assert-True (
        $protectedControlResult.ExitCode -eq 0 -and
        $protectedControlResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $protectedControlResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'capability-not-granted'
        )
    ) 'A workspace grant must not authorize writes to live governance controls.'

    $protectedStateWrite = New-HookPayload -Event 'PreToolUse' `
        -SessionId $enforcedSession `
        -ToolUseId 'codex-tool-call-protected-state' `
        -ToolName 'apply_patch' `
        -ToolInput ([pscustomobject]@{
            command = "*** Begin Patch`n*** Add File: .local/governance/task-authorizations/codex/forged.json`n+{}`n*** End Patch"
        })
    $protectedStateResult = Invoke-HostHook -HostName codex `
        -Payload $protectedStateWrite
    $protectedStateResponse = $protectedStateResult.Stdout | ConvertFrom-Json
    Assert-True (
        $protectedStateResult.ExitCode -eq 0 -and
        $protectedStateResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $protectedStateResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'unclassified-effect'
        )
    ) 'No task grant may authorize direct writes to runtime authorization state.'

    $deniedPush = New-HookPayload -Event 'PreToolUse' `
        -SessionId $enforcedSession `
        -ToolUseId 'codex-tool-call-denied-push' `
        -ToolName 'Bash' `
        -ToolInput ([pscustomobject]@{ command = 'git push origin HEAD' })
    $deniedPushResult = Invoke-HostHook -HostName codex -Payload $deniedPush
    Assert-True ($deniedPushResult.ExitCode -eq 0) (
        'Codex deny must use a successful structured hook response on Windows.'
    )
    $deniedHookResponse = $deniedPushResult.Stdout | ConvertFrom-Json
    Assert-True (
        $deniedHookResponse.hookSpecificOutput.hookEventName -ceq 'PreToolUse' -and
        $deniedHookResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $deniedHookResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'capability-not-granted'
        )
    ) (
        'The denied repository mutation must return Codex structured deny output.'
    )
    $deniedDecisions = @(Get-HostPolicyDecisions -HostName codex | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
    } | Where-Object {
        $_.request.capability -ceq 'repository-mutate' -and
        $_.coverage.enforcement -ceq 'enforced'
    })
    Assert-True (
        $deniedDecisions.Count -ge 1 -and
        $deniedDecisions[-1].decision.outcome -ceq 'deny'
    ) 'Ungrantable effect must leave durable deny evidence before returning deny.'

    $malformedPreResult = Invoke-ScriptProcess -ScriptPath $hook -Arguments @(
        '-HostName', 'codex',
        '-ProjectRoot', $tempRoot,
        '-SchemaPath', $schema,
        '-RuntimePolicySchemaPath', $runtimePolicySchema,
        '-TaskAuthorizationSchemaPath', $taskAuthorizationSchema,
        '-ExpectedEventName', 'PreToolUse'
    ) -StandardInput '{'
    $malformedPreResponse = $malformedPreResult.Stdout | ConvertFrom-Json
    Assert-True (
        $malformedPreResult.ExitCode -eq 0 -and
        $malformedPreResponse.hookSpecificOutput.permissionDecision -ceq 'deny' -and
        $malformedPreResponse.hookSpecificOutput.permissionDecisionReason.Contains(
            'internal-error'
        )
    ) 'Codex PreToolUse protocol errors must fail closed with structured deny.'

    [void](Write-TaskAuthorizationFixture -HostName claude `
        -SessionId 'claude-session-contract' `
        -Capability 'workspace-write' `
        -TargetClass 'workspace-file')
    $claudeInput = [pscustomobject][ordered]@{
        file_path = (Join-Path $tempRoot 'fixture.txt')
        content = 'fixture content'
    }
    $claudePre = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'claude-session-contract' `
        -ToolUseId 'claude-tool-call-one' `
        -ToolName 'Write' `
        -ToolInput $claudeInput
    $claudePreResult = Invoke-HostHook -HostName claude -Payload $claudePre
    Assert-True ($claudePreResult.ExitCode -eq 0) (
        "Claude PreToolUse must persist: $($claudePreResult.Stderr)"
    )
    $claudeFailure = New-HookPayload -Event 'PostToolUseFailure' `
        -SessionId 'claude-session-contract' `
        -ToolUseId 'claude-tool-call-one' `
        -ToolName 'Write' `
        -ToolInput $claudeInput `
        -ErrorText 'fixture failure with raw output that must not persist'
    $claudeFailureResult = Invoke-HostHook -HostName claude `
        -Payload $claudeFailure
    Assert-True ($claudeFailureResult.ExitCode -eq 0) (
        "Claude failure observation must close the intent: " +
            $claudeFailureResult.Stderr
    )
    $claudeLogs = Get-HostLogs -HostName claude
    Assert-True ($claudeLogs.Count -eq 1) 'Claude hook must create one log.'
    $claudeDocument = Get-Content -Raw -LiteralPath $claudeLogs[0].FullName |
        ConvertFrom-Json
    Assert-True (
        $claudeDocument.records[2].result -ceq 'failed' -and
        $claudeDocument.records[2].evidence_code -ceq 'claude-tool-failed'
    ) 'PostToolUseFailure must record a metadata-only failed result.'
    Assert-True (-not (
        (Get-Content -Raw -LiteralPath $claudeLogs[0].FullName).Contains(
            'fixture failure with raw output'
        )
    )) 'Raw failure output must not be persisted.'

    $parallelPre = New-HookPayload -Event 'PreToolUse' `
        -SessionId 'claude-session-contract' `
        -ToolUseId 'claude-tool-call-two' `
        -ToolName 'Read' `
        -ToolInput ([pscustomobject]@{ file_path = $schema })
    $parallelResult = Invoke-HostHook -HostName claude -Payload $parallelPre
    Assert-True ($parallelResult.ExitCode -eq 0) (
        'Independent tool identities must use independent single-writer logs.'
    )
    Assert-True ((Get-HostLogs -HostName claude).Count -eq 2) (
        'Parallel-capable calls must not contend for one session-wide operation log.'
    )

    $invalidPayload = Copy-JsonValue -Value $parallelPre
    $invalidPayload.PSObject.Properties.Remove('tool_use_id')
    $invalidResult = Invoke-HostHook -HostName claude -Payload $invalidPayload
    Assert-True ($invalidResult.ExitCode -eq 2) (
        'Missing stable tool identity must fail closed before execution.'
    )

    $codex = Get-Content -Raw -LiteralPath $codexConfig | ConvertFrom-Json
    foreach ($event in @('PreToolUse', 'PostToolUse')) {
        $entries = @($codex.hooks.$event)
        Assert-True ($entries.Count -eq 1) "Codex must register $event once."
        Assert-True ($entries[0].matcher -ceq '*') (
            "Codex $event must cover every supported local tool path."
        )
        Assert-True (-not [bool]$entries[0].hooks[0].async) (
            "Codex $event durability hook must be synchronous."
        )
        Assert-True ($entries[0].hooks[0].command.Contains(
            'governance-host-operation-hook.ps1'
        )) "Codex $event must invoke the shared handler."
        Assert-True ($entries[0].hooks[0].command.Contains(
            "-ExpectedEventName $event"
        )) "Codex $event must identify its configured hook phase."
        $windowsCommand = [string]$entries[0].hooks[0].commandWindows
        Assert-True (-not $windowsCommand.Contains('"')) (
            "Codex $event commandWindows must not contain embedded quotes; " +
                'Codex 0.145.0 wraps the command for cmd.exe /C and misparses them.'
        )
        Assert-True ($windowsCommand.StartsWith('powershell.exe ')) (
            "Codex $event must use Windows PowerShell for its encoded bootstrap."
        )
        $encodedMatch = [regex]::Match(
            $windowsCommand,
            '(?i)(?:^|\s)-EncodedCommand\s+(?<payload>[A-Za-z0-9+/=]+)\s*$'
        )
        Assert-True $encodedMatch.Success (
            "Codex $event must use a quote-free encoded Windows bootstrap."
        )
        $bootstrapScript = [Text.Encoding]::Unicode.GetString(
            [Convert]::FromBase64String($encodedMatch.Groups['payload'].Value)
        )
        Assert-True (
            $bootstrapScript.Contains("`$ProgressPreference='SilentlyContinue'") -and
            $bootstrapScript.Contains('git rev-parse --show-toplevel') -and
            $bootstrapScript.Contains('scripts\codex-governance-hook.cmd') -and
            $bootstrapScript.EndsWith(" host $event; exit `$LASTEXITCODE")
        ) (
            "Codex $event bootstrap must resolve the repository root before " +
                'invoking the Windows host launcher and propagate its exit code.'
        )
    }

    $claude = Get-Content -Raw -LiteralPath $claudeConfig | ConvertFrom-Json
    foreach ($event in @('PreToolUse', 'PostToolUse', 'PostToolUseFailure')) {
        $entries = @($claude.hooks.$event)
        Assert-True ($entries.Count -eq 1) "Claude must register $event once."
        Assert-True ($entries[0].matcher -ceq '*') (
            "Claude $event must cover every hook-visible tool path."
        )
        Assert-True (-not [bool]$entries[0].hooks[0].async) (
            "Claude $event durability hook must be synchronous."
        )
        Assert-True (
            @($entries[0].hooks[0].args) -contains 'claude'
        ) "Claude $event must invoke the shared handler as Claude."
    }

    '[PASS] host hooks: pre-effect intent and post-effect result are durable'
    '[PASS] privacy: raw tool arguments, output, and errors are not persisted'
    '[PASS] recovery: duplicate delivery is idempotent and mismatch fails closed'
    '[PASS] coverage: Codex and Claude repository hook configs are synchronous'
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
        (Split-Path $resolvedTempRoot -Leaf) -like
            'governance-host-operation-hook-*'
    ) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
