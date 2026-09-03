[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$schema = Join-Path $core 'evals\schemas\governance-runtime-policy-decisions.schema.json'
$authorizationSchema = Join-Path $core 'evals\schemas\governance-task-authorizations.schema.json'
$runtimePolicyModule = Join-Path $core 'scripts\lib\RuntimePolicy.psm1'
$authorizationIssuer = Join-Path $core 'scripts\governance-task-authorization.ps1'
$codexLivePilot = Join-Path $core 'docs\operations\runtime-governance-v2-codex-live-pilot.md'
Import-Module (Join-Path $core 'scripts\lib\GovernanceCommon.psm1') -Force
Import-Module $runtimePolicyModule -Force
$runtimePolicyDigest = Get-ProjectDRuntimePolicyDigest -ProjectRoot $core

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

Assert-True ($runtimePolicyDigest -match '^sha256:[a-f0-9]{64}$') (
    'The current policy bundle must have a deterministic SHA-256 identity.'
)

function New-Decision {
    return [ordered]@{
        schema_version = 1
        decision_id = 'decision-contract-one'
        task_ref = 'task-contract'
        host_run_id = 'host-run-contract'
        operation_ref = 'operation-contract'
        policy = [ordered]@{
            policy_id = 'projectd-runtime-policy'
            policy_version = 1
            policy_digest = 'sha256:' + ('a' * 64)
        }
        request = [ordered]@{
            capability = 'workspace-write'
            target_class = 'workspace-file'
            effect = [ordered]@{
                durable = $true
                external = $false
                destructive = $true
                reversible = 'yes'
            }
        }
        authorization = [ordered]@{
            state = 'verified'
            basis = 'explicit-current-task'
            scope_match = 'exact'
        }
        decision = [ordered]@{
            outcome = 'allow'
            reason_codes = @('authorized-task-scope')
        }
        coverage = [ordered]@{
            classification_source = 'operation-payload'
            enforcement = 'enforced'
            host_observable = $true
        }
        privacy = [ordered]@{
            content_mode = 'metadata-only'
            contains_raw_prompt = $false
            contains_chain_of_thought = $false
            contains_secret_values = $false
            contains_tool_arguments = $false
            contains_tool_output = $false
        }
    }
}

Assert-True (Test-Path -LiteralPath $schema -PathType Leaf) 'Runtime policy schema must exist.'
Assert-True (Test-Path -LiteralPath $authorizationSchema -PathType Leaf) 'Task authorization schema must exist.'

$authorizationEnvelope = [ordered]@{
    schema_version = 1
    authorization_id = 'authorization-contract-one'
    source_decision_id = 'decision-contract-one'
    task_ref = 'task-contract'
    host_run_id = 'host-run-contract'
    issued_at = [DateTimeOffset]::UtcNow.ToString('o')
    expires_at = [DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')
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
            capability = 'workspace-write'
            target_class = 'workspace-file'
            allow_external = $false
            allow_destructive = $false
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
Assert-True (Test-Json -Json ($authorizationEnvelope | ConvertTo-Json -Depth 32) `
    -SchemaFile $authorizationSchema -ErrorAction Stop) (
    'A bounded task-scoped authorization envelope must validate.'
)
$missingExpiry = $authorizationEnvelope | ConvertTo-Json -Depth 32 |
    ConvertFrom-Json
$missingExpiry.PSObject.Properties.Remove('expires_at')
Assert-True (-not (Test-Json -Json ($missingExpiry | ConvertTo-Json -Depth 32) `
    -SchemaFile $authorizationSchema -ErrorAction SilentlyContinue)) (
    'A task authorization envelope without expiry must be rejected.'
)
$missingEffectFlag = $authorizationEnvelope | ConvertTo-Json -Depth 32 |
    ConvertFrom-Json
$missingEffectFlag.grants[0].PSObject.Properties.Remove('allow_external')
Assert-True (-not (Test-Json `
    -Json ($missingEffectFlag | ConvertTo-Json -Depth 32) `
    -SchemaFile $authorizationSchema -ErrorAction SilentlyContinue)) (
    'Every grant must explicitly state its external and destructive bounds.'
)
$unsafeProductionEnvelope = $authorizationEnvelope | ConvertTo-Json -Depth 32 |
    ConvertFrom-Json
$unsafeProductionEnvelope.authorization.authorized_by = 'user'
$unsafeProductionEnvelope.grants[0].capability = 'production-mutate'
Assert-True (-not (Test-Json `
    -Json ($unsafeProductionEnvelope | ConvertTo-Json -Depth 32) `
    -SchemaFile $authorizationSchema -ErrorAction SilentlyContinue)) (
    'Production authorization must explicitly grant external and destructive effects.'
)
Assert-True (Test-Path -LiteralPath $runtimePolicyModule -PathType Leaf) (
    'Runtime policy normalization module must exist.'
)

function Get-RuntimeRequestFromJson {
    param(
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)][string]$ToolInputJson
    )
    $document = [Text.Json.JsonDocument]::Parse($ToolInputJson)
    try {
        return Get-ProjectDRuntimeRequest -ToolName $ToolName `
            -ToolInput $document.RootElement -ProjectRoot $core
    } finally {
        $document.Dispose()
    }
}

$readRequest = Get-RuntimeRequestFromJson -ToolName 'Read' `
    -ToolInputJson '{"file_path":"README.md"}'
Assert-True (
    $readRequest.capability -ceq 'local-read' -and
    $readRequest.decision_outcome -ceq 'observe-only'
) 'Local reads must normalize as non-mutating local-read capability.'

$codexBootstrapRequest = Get-RuntimeRequestFromJson `
    -ToolName 'list_mcp_resources' -ToolInputJson '{}'
Assert-True (
    $codexBootstrapRequest.capability -ceq 'network-read' -and
    $codexBootstrapRequest.decision_outcome -ceq 'observe-only' -and
    $codexBootstrapRequest.effect.external
) (
    'The pinned Codex bootstrap tool must remain a benign observed source ' +
    'operation.'
)
Assert-True (Test-Path -LiteralPath $codexLivePilot -PathType Leaf) (
    'The Codex live-pilot runbook must exist.'
)
$codexLivePilotText = Get-Content -Raw -LiteralPath $codexLivePilot
$codexBootstrapSectionMatch = [regex]::Match(
    $codexLivePilotText,
    '(?ms)^## 7\. Bootstrap：先證明 hook 真正載入\s*(?<section>.*?)^## 8\.'
)
Assert-True $codexBootstrapSectionMatch.Success (
    'The Codex live-pilot runbook must retain a bounded bootstrap section.'
)
$codexBootstrapSection = $codexBootstrapSectionMatch.Groups['section'].Value
$expectedCodexBootstrapPrompt = @'
> Call `codex.list_mcp_resources` exactly once with an empty input (`{}`). Report only the number of returned resources. Do not call any other tool, including DevSpace, CodeGraph, GitHub, web, or shell. Do not modify files.
'@.Trim()
Assert-True (
    $codexBootstrapSection.Contains($expectedCodexBootstrapPrompt) -and
    $codexBootstrapSection.Contains('list_mcp_resources')
) (
    'The Codex live-pilot bootstrap section must retain the exact prompt and ' +
    'normalized name of its deterministic source tool.'
)
Assert-True (
    $codexBootstrapSection.Contains('$bootstrapEffectResults') -and
    $codexBootstrapSection.Contains("'effect-result'") -and
    $codexBootstrapSection.Contains("'succeeded'") -and
    $codexBootstrapSection.Contains('pending_effect_id')
) (
    'The Codex live-pilot bootstrap must prove that its single operation ' +
    'completed successfully without a pending effect.'
)

$codexAllowSectionMatch = [regex]::Match(
    $codexLivePilotText,
    '(?ms)^## 9\. Live allow case\s*(?<section>.*?)^## 10\.'
)
Assert-True $codexAllowSectionMatch.Success (
    'The Codex live-pilot runbook must retain a bounded allow section.'
)
$codexAllowSection = $codexAllowSectionMatch.Groups['section'].Value
$expectedCodexAllowPrompt = @'
> Use the built-in `apply_patch` tool exactly once to add the file `.local/governance/pilot/codex-live-allow.txt` with the single line `runtime-governance-v2-allow`. Do not call DevSpace, CodeGraph, GitHub, web, shell, or any other tool. Do not modify tracked repository files.
'@.Trim()
Assert-True $codexAllowSection.Contains($expectedCodexAllowPrompt) (
    'The Codex live-pilot allow section must pin the canonical apply_patch ' +
    'tool and forbid fallback tool routes.'
)

$webReadRequest = Get-RuntimeRequestFromJson -ToolName 'web_fetch' `
    -ToolInputJson '{"url":"https://example.invalid"}'
Assert-True (
    $webReadRequest.capability -ceq 'network-read' -and
    $webReadRequest.effect.external
) 'Web fetch must normalize as network-read rather than generic Action.'

$gitPushRequest = Get-RuntimeRequestFromJson -ToolName 'Bash' `
    -ToolInputJson '{"command":"git push origin HEAD"}'
Assert-True (
    $gitPushRequest.capability -ceq 'repository-mutate' -and
    $gitPushRequest.effect.external -and
    $gitPushRequest.decision_outcome -ceq 'require-authorization'
) 'Repository mutation must be detected from command payload.'

$genericCommandRequest = Get-RuntimeRequestFromJson -ToolName 'Bash' `
    -ToolInputJson '{"command":"custom-tool --do-something"}'
Assert-True (
    $genericCommandRequest.capability -ceq 'command-execute' -and
    $genericCommandRequest.effect.external -and
    $genericCommandRequest.effect.destructive
) 'An arbitrary command grant must disclose its open-world external/destructive power.'

$mcpMutationRequest = Get-RuntimeRequestFromJson `
    -ToolName 'mcp__threads__create' -ToolInputJson '{}'
Assert-True (
    $mcpMutationRequest.capability -ceq 'external-write' -and
    $mcpMutationRequest.effect.external
) 'Mutation tokens must win over read-like substrings in MCP tool names.'

$browserClickRequest = Get-RuntimeRequestFromJson `
    -ToolName 'browser_click' -ToolInputJson '{}'
Assert-True (
    $browserClickRequest.capability -ceq 'external-write' -and
    $browserClickRequest.effect.external
) 'Ambiguous browser interactions must not be classified as network reads.'

$codexPatchCommand = Get-RuntimeRequestFromJson -ToolName 'apply_patch' `
    -ToolInputJson '{"command":"*** Begin Patch\n*** Add File: .local/governance/pilot/contract.txt\n+ok\n*** End Patch"}'
Assert-True (
    $codexPatchCommand.capability -ceq 'workspace-write' -and
    $codexPatchCommand.target_class -ceq 'workspace-file'
) (
    'The canonical Codex apply_patch tool_input.command payload must ' +
    'normalize as a workspace write.'
)

$ordinaryPatch = Get-RuntimeRequestFromJson -ToolName 'apply_patch' `
    -ToolInputJson '{"patch":"*** Begin Patch\n*** Add File: .local/governance/pilot/contract.txt\n+ok\n*** End Patch"}'
Assert-True (
    $ordinaryPatch.capability -ceq 'workspace-write' -and
    $ordinaryPatch.target_class -ceq 'workspace-file'
) 'A parsed ordinary repository patch must remain a workspace write.'

$conflictingPatchFields = Get-RuntimeRequestFromJson -ToolName 'apply_patch' `
    -ToolInputJson '{"command":"*** Begin Patch\n*** Add File: ordinary.txt\n+ok\n*** End Patch","patch":"*** Begin Patch\n*** Update File: scripts/lib/RuntimePolicy.psm1\n@@\n-old\n+tamper\n*** End Patch"}'
Assert-True (
    $conflictingPatchFields.capability -ceq 'unclassified-effect' -and
    $conflictingPatchFields.target_class -ceq 'unclassified-target'
) (
    'Conflicting canonical and compatibility patch fields must fail closed.'
)

$governancePatch = Get-RuntimeRequestFromJson -ToolName 'apply_patch' `
    -ToolInputJson '{"patch":"*** Begin Patch\n*** Update File: scripts/lib/RuntimePolicy.psm1\n@@\n-test\n+tamper\n*** End Patch"}'
Assert-True (
    $governancePatch.capability -ceq 'repository-mutate' -and
    $governancePatch.target_class -ceq 'governance-control'
) 'A write to the live governance control plane must require a separate grant.'

$authorizationStatePatch = Get-RuntimeRequestFromJson -ToolName 'apply_patch' `
    -ToolInputJson '{"patch":"*** Begin Patch\n*** Add File: .local/governance/task-authorizations/codex/forged.json\n+{}\n*** End Patch"}'
Assert-True (
    $authorizationStatePatch.capability -ceq 'unclassified-effect' -and
    $authorizationStatePatch.target_class -ceq 'runtime-governance-state'
) 'Agent tools must never receive a grantable capability for authorization state.'

$unknownMcpRequest = Get-RuntimeRequestFromJson -ToolName 'mcp_tool' `
    -ToolInputJson '{}'
Assert-True (
    $unknownMcpRequest.capability -ceq 'unclassified-effect' -and
    $unknownMcpRequest.classification_source -ceq 'unclassified' -and
    $unknownMcpRequest.decision_outcome -ceq 'require-authorization'
) 'Unknown MCP operations must remain fail-safe and unclassified.'

$noEnvelopeDecision = Resolve-ProjectDRuntimeAuthorization `
    -RuntimeRequest $ordinaryPatch -TaskRef 'task-contract' `
    -HostRunId 'host-run-contract' -PolicyDigest $runtimePolicyDigest
Assert-True (
    $noEnvelopeDecision.state -ceq 'not-authorized' -and
    $noEnvelopeDecision.outcome -ceq 'deny' -and
    $noEnvelopeDecision.enforcement -ceq 'enforced'
) 'Effectful requests without a task envelope must fail closed.'

$authorizedDecision = Resolve-ProjectDRuntimeAuthorization `
    -RuntimeRequest $ordinaryPatch -Envelope ([pscustomobject]$authorizationEnvelope) `
    -TaskRef 'task-contract' -HostRunId 'host-run-contract' `
    -PolicyDigest $runtimePolicyDigest -AllowContractAuthorizationFixture
Assert-True (
    $authorizedDecision.state -ceq 'verified' -and
    $authorizedDecision.outcome -ceq 'allow' -and
    $authorizedDecision.enforcement -ceq 'enforced'
) 'A matching, current, bounded contract envelope must allow its exact grant.'

$unrelatedReadDecision = Resolve-ProjectDRuntimeAuthorization `
    -RuntimeRequest $webReadRequest `
    -Envelope ([pscustomobject]$authorizationEnvelope) `
    -TaskRef 'task-contract' -HostRunId 'host-run-contract' `
    -PolicyDigest $runtimePolicyDigest -AllowContractAuthorizationFixture
Assert-True (
    $unrelatedReadDecision.state -ceq 'unavailable' -and
    $unrelatedReadDecision.outcome -ceq 'observe-only' -and
    $unrelatedReadDecision.enforcement -ceq 'advisory'
) (
    'An unrelated effect grant must not promote a read into verified authority.'
)

$liveFixtureDecision = Resolve-ProjectDRuntimeAuthorization `
    -RuntimeRequest $ordinaryPatch -Envelope ([pscustomobject]$authorizationEnvelope) `
    -TaskRef 'task-contract' -HostRunId 'host-run-contract' `
    -PolicyDigest $runtimePolicyDigest
Assert-True (
    $liveFixtureDecision.outcome -ceq 'deny' -and
    $liveFixtureDecision.reason_codes -contains `
        'contract-authorization-not-accepted-live'
) 'A contract fixture must not be accepted as live user authorization.'

$stalePolicyEnvelope = $authorizationEnvelope | ConvertTo-Json -Depth 32 |
    ConvertFrom-Json
$stalePolicyEnvelope.policy.policy_digest = 'sha256:' + ('f' * 64)
$stalePolicyDecision = Resolve-ProjectDRuntimeAuthorization `
    -RuntimeRequest $ordinaryPatch -Envelope $stalePolicyEnvelope `
    -TaskRef 'task-contract' -HostRunId 'host-run-contract' `
    -PolicyDigest $runtimePolicyDigest -AllowContractAuthorizationFixture
Assert-True (
    $stalePolicyDecision.outcome -ceq 'deny' -and
    $stalePolicyDecision.reason_codes -contains `
        'authorization-envelope-policy-mismatch'
) 'An envelope issued for another policy digest must fail closed.'

$valid = New-Decision
$validJson = $valid | ConvertTo-Json -Depth 32
Assert-True (Test-Json -Json $validJson -SchemaFile $schema -ErrorAction Stop) (
    'A task-scoped workspace-write decision must validate.'
)

$unclassified = New-Decision
$unclassified.request.capability = 'unclassified-effect'
$unclassified.authorization.state = 'unavailable'
$unclassified.authorization.basis = 'unavailable'
$unclassified.authorization.scope_match = 'unknown'
$unclassified.decision.outcome = 'require-authorization'
$unclassified.decision.reason_codes = @('unclassified-effect')
$unclassified.coverage.classification_source = 'unclassified'
$unclassified.coverage.enforcement = 'advisory'
$unclassifiedJson = $unclassified | ConvertTo-Json -Depth 32
Assert-True (Test-Json -Json $unclassifiedJson -SchemaFile $schema -ErrorAction Stop) (
    'An unknown operation must remain representable without pretending it is classified.'
)

$hostPermissionOnly = New-Decision
$hostPermissionOnly.authorization.state = 'pending'
$hostPermissionOnly.authorization.basis = 'host-permission-only'
$hostPermissionOnly.authorization.scope_match = 'unknown'
$hostPermissionOnly.decision.outcome = 'require-authorization'
$hostPermissionOnly.decision.reason_codes = @('host-permission-is-not-task-authorization')
$hostPermissionJson = $hostPermissionOnly | ConvertTo-Json -Depth 32
Assert-True (Test-Json -Json $hostPermissionJson -SchemaFile $schema -ErrorAction Stop) (
    'Host permission must be representable separately from verified projectD authorization.'
)

$invalidCapability = New-Decision
$invalidCapability.request.capability = 'generic-action'
$invalidJson = $invalidCapability | ConvertTo-Json -Depth 32
Assert-True (-not (Test-Json -Json $invalidJson -SchemaFile $schema -ErrorAction SilentlyContinue)) (
    'The runtime contract must reject the old generic Action classification as a capability.'
)

$hostPermissionEscalation = New-Decision
$hostPermissionEscalation.authorization.basis = 'host-permission-only'
$hostPermissionEscalation.authorization.state = 'verified'
$hostPermissionEscalation.authorization.scope_match = 'exact'
$hostPermissionEscalation.decision.outcome = 'allow'
$hostPermissionEscalation.decision.reason_codes = @('host-permitted')
$hostPermissionEscalationJson = $hostPermissionEscalation | ConvertTo-Json -Depth 32
Assert-True (-not (Test-Json -Json $hostPermissionEscalationJson -SchemaFile $schema -ErrorAction SilentlyContinue)) (
    'Host permission alone must never validate as an allowed, verified task authorization.'
)

$unclassifiedAllow = New-Decision
$unclassifiedAllow.request.capability = 'unclassified-effect'
$unclassifiedAllowJson = $unclassifiedAllow | ConvertTo-Json -Depth 32
Assert-True (-not (Test-Json -Json $unclassifiedAllowJson -SchemaFile $schema -ErrorAction SilentlyContinue)) (
    'An unclassified effect must never validate with an allow outcome.'
)

$productionPending = New-Decision
$productionPending.request.capability = 'production-mutate'
$productionPending.authorization.state = 'unavailable'
$productionPending.authorization.basis = 'unavailable'
$productionPending.authorization.scope_match = 'unknown'
$productionPending.decision.outcome = 'require-authorization'
$productionPending.decision.reason_codes = @('explicit-authorization-required')
$productionPending.coverage.enforcement = 'advisory'
$productionPendingJson = $productionPending | ConvertTo-Json -Depth 32
Assert-True (Test-Json -Json $productionPendingJson -SchemaFile $schema -ErrorAction Stop) (
    'An unverified production mutation request must remain representable while requiring authorization.'
)

$productionWithoutExplicitScope = New-Decision
$productionWithoutExplicitScope.request.capability = 'production-mutate'
$productionWithoutExplicitScope.authorization.basis = 'task-derived-low-risk'
$productionWithoutExplicitScope.authorization.scope_match = 'derived'
$productionJson = $productionWithoutExplicitScope | ConvertTo-Json -Depth 32
Assert-True (-not (Test-Json -Json $productionJson -SchemaFile $schema -ErrorAction SilentlyContinue)) (
    'An allowed production mutation requires exact explicit current-task authorization.'
)

$privacyLeak = New-Decision
$privacyLeak.privacy.contains_tool_arguments = $true
$privacyLeakJson = $privacyLeak | ConvertTo-Json -Depth 32
Assert-True (-not (Test-Json -Json $privacyLeakJson -SchemaFile $schema -ErrorAction SilentlyContinue)) (
    'Runtime policy evidence must reject raw tool arguments.'
)

Assert-True (Test-Path -LiteralPath $authorizationIssuer -PathType Leaf) (
    'The bounded task authorization issuer must exist.'
)
$pwsh = Get-Command pwsh -ErrorAction Stop
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $pwsh.Source
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in @(
    '-NoProfile', '-File', $authorizationIssuer,
    '-HostName', 'codex',
    '-DecisionPath', (Join-Path $core 'missing-decision.json'),
    '-Capability', 'workspace-write',
    '-TargetClass', 'workspace-file',
    '-ExplicitUserAuthorization'
)) {
    [void]$startInfo.ArgumentList.Add($argument)
}
$issuerProcess = [Diagnostics.Process]::Start($startInfo)
$issuerProcess.StandardInput.Close()
$issuerStdout = $issuerProcess.StandardOutput.ReadToEndAsync()
$issuerStderr = $issuerProcess.StandardError.ReadToEndAsync()
if (-not $issuerProcess.WaitForExit(15000)) {
    $issuerProcess.Kill($true)
    throw 'The redirected authorization issuer test timed out.'
}
$issuerError = $issuerStderr.GetAwaiter().GetResult()
[void]$issuerStdout.GetAwaiter().GetResult()
Assert-True (
    $issuerProcess.ExitCode -ne 0 -and
    $issuerError -match '(?i)interactive|互動'
) 'A redirected agent/tool process must not be able to self-issue authorization.'

Write-Output 'governance-runtime-policy.contract: PASS'
