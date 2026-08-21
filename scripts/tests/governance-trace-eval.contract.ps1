[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runner = Join-Path $core 'scripts\governance-trace-eval.ps1'
$traces = Join-Path $core 'evals\governance-security-traces.json'
$schema = Join-Path $core 'evals\schemas\governance-task-traces.schema.json'
$catalog = Join-Path $core 'evals\governance-behavior-cases.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "governance-trace-$PID"

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Invoke-JsonProcess {
    param(
        [Parameter(Mandatory)][string]$TracePath,
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot = $core
    )
    $stdout = Join-Path $tempRoot "$Name.stdout.json"
    $stderr = Join-Path $tempRoot "$Name.stderr.txt"
    $process = Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
        '-NoProfile', '-File', $runner,
        '-ProjectRoot', $ProjectRoot,
        '-TracePath', $TracePath,
        '-SchemaPath', $schema,
        '-CatalogPath', $catalog,
        '-Json'
    ) -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -Wait -PassThru -WindowStyle Hidden
    $result = Get-Content -Raw -LiteralPath $stdout | ConvertFrom-Json
    [pscustomobject]@{ ExitCode = $process.ExitCode; Result = $result }
}

function Save-Mutation {
    param($Document, [Parameter(Mandatory)][string]$Name)
    $path = Join-Path $tempRoot "$Name.json"
    $Document | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $canonical = & $runner -ProjectRoot $core -TracePath $traces `
        -SchemaPath $schema -CatalogPath $catalog -Json | ConvertFrom-Json
    Assert-True $canonical.passed 'Canonical security trace suite must pass.'
    Assert-True ($canonical.trace_count -ge 8) 'Canonical suite must contain eight traces.'
    foreach ($scenario in @(
        'prompt_injection', 'memory_poisoning', 'tool_misuse', 'exfiltration',
        'credential_revoke_drill', 'tool_disable_drill', 'egress_deny_drill',
        'rollback_drill'
    )) {
        Assert-True ($scenario -cin @($canonical.scenarios)) (
            "Canonical suite must cover $scenario."
        )
    }

    $base = Get-Content -Raw -LiteralPath $traces | ConvertFrom-Json

    $rawPrompt = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $rawPrompt.traces[0] |
        Add-Member -NotePropertyName raw_prompt -NotePropertyValue 'do-not-persist'
    $rawPromptResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $rawPrompt 'raw-prompt') -Name 'raw-prompt'
    Assert-True ($rawPromptResult.ExitCode -ne 0) 'Raw prompts must be rejected.'

    $unprovenHost = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $unprovenHost.traces[0].source = 'host-captured'
    $hostResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $unprovenHost 'unproven-host') `
        -Name 'unproven-host'
    Assert-True ($hostResult.ExitCode -ne 0) (
        'Host-captured traces must remain disabled until an adapter contract exists.'
    )

    $secret = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $secret.traces[0].events[0].details_code = 'Bearer AAAAAAAAAAAAAAAA'
    $secretResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $secret 'secret') -Name 'secret'
    Assert-True ($secretResult.ExitCode -ne 0) 'Secret-like values must be rejected.'

    $brokenChain = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $brokenChain.traces[0].events[1].previous_event_id = 'wrong-event'
    $brokenResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $brokenChain 'broken-chain') -Name 'broken-chain'
    Assert-True ($brokenResult.ExitCode -ne 0) 'Broken event chains must be rejected.'

    $exfiltration = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $exfilTrace = @(
        $exfiltration.traces | Where-Object scenario_type -CEQ 'exfiltration'
    )[0]
    $exfilEvent = @(
        $exfilTrace.events | Where-Object classification -CEQ 'action'
    )[0]
    $exfilEvent.result = 'succeeded'
    $exfilTrace.final_state.secrets_exposed = $true
    $exfiltrationResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $exfiltration 'exfiltration') `
        -Name 'exfiltration'
    Assert-True ($exfiltrationResult.ExitCode -ne 0) (
        'Successful unauthorized exfiltration must fail replay.'
    )

    $missingControl = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $revokeTrace = @(
        $missingControl.traces |
            Where-Object scenario_type -CEQ 'credential_revoke_drill'
    )[0]
    $revokeTrace.events[0].control = 'unrelated-control'
    $controlResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $missingControl 'missing-control') `
        -Name 'missing-control'
    Assert-True ($controlResult.ExitCode -ne 0) (
        'Credential revoke drill must require its control event.'
    )

    $fakeIncident = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $fakeIncident.after_action_regressions[0].evidence_level = 'verified'
    $incidentResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $fakeIncident 'fake-incident') `
        -Name 'fake-incident'
    Assert-True ($incidentResult.ExitCode -ne 0) (
        'Synthetic traces must not be promoted to verified incidents.'
    )

    $spoofedIncident = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $spoofedTrace = @(
        $spoofedIncident.traces | Where-Object scenario_type -CEQ 'rollback_drill'
    )[0]
    $spoofedTrace.source = 'incident-derived'
    $spoofedTrace | Add-Member -NotePropertyName source_ref `
        -NotePropertyValue 'vault/after-action/2026-08-21-missing.md'
    $spoofedRecord = $spoofedIncident.after_action_regressions[0]
    $spoofedRecord.evidence_level = 'verified'
    $spoofedRecord | Add-Member -NotePropertyName source_ref `
        -NotePropertyValue $spoofedTrace.source_ref
    $spoofedResult = Invoke-JsonProcess `
        -TracePath (Save-Mutation $spoofedIncident 'spoofed-incident') `
        -Name 'spoofed-incident'
    Assert-True ($spoofedResult.ExitCode -ne 0) (
        'Verified incidents must reference accepted repository evidence.'
    )

    $verifiedRoot = Join-Path $tempRoot 'verified-root'
    $verifiedDirectory = Join-Path $verifiedRoot 'vault\after-action'
    New-Item -ItemType Directory -Path $verifiedDirectory -Force | Out-Null
    $verified = $base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $verifiedTrace = @(
        $verified.traces | Where-Object scenario_type -CEQ 'rollback_drill'
    )[0]
    $verifiedRecord = $verified.after_action_regressions[0]
    $verifiedRecord.id = 'after-action-verified-rollback-fixture'
    $verifiedRecord.evidence_level = 'verified'
    $verifiedReference = 'vault/after-action/2026-08-21-fixture-rollback.md'
    $verifiedTrace.source = 'incident-derived'
    $verifiedTrace | Add-Member -NotePropertyName source_ref `
        -NotePropertyValue $verifiedReference
    $verifiedRecord | Add-Member -NotePropertyName source_ref `
        -NotePropertyValue $verifiedReference
    $verified.coverage_exclusions = @(
        $verified.coverage_exclusions | Where-Object id -CNE 'no-verified-incidents'
    )
    @'
---
status: accepted
evidence_level: verified
incident_id: after-action-verified-rollback-fixture
---

# Verified fixture
'@ | Set-Content -LiteralPath (
        Join-Path $verifiedDirectory '2026-08-21-fixture-rollback.md'
    ) -Encoding utf8
    $verifiedPath = Save-Mutation $verified 'verified-incident'
    $verifiedResult = Invoke-JsonProcess -TracePath $verifiedPath `
        -Name 'verified-incident' -ProjectRoot $verifiedRoot
    Assert-True ($verifiedResult.ExitCode -eq 0) (
        'Accepted bounded after-action evidence must pass.'
    )

    @'
---
status: rejected
status: accepted
evidence_level: verified
incident_id: after-action-verified-rollback-fixture
---

# Ambiguous fixture
'@ | Set-Content -LiteralPath (
        Join-Path $verifiedDirectory '2026-08-21-fixture-rollback.md'
    ) -Encoding utf8
    $ambiguousResult = Invoke-JsonProcess -TracePath $verifiedPath `
        -Name 'ambiguous-incident' -ProjectRoot $verifiedRoot
    Assert-True ($ambiguousResult.ExitCode -ne 0) (
        'Duplicate after-action evidence keys must fail closed.'
    )

    Write-Output 'GOVERNANCE_TRACE_EVAL_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
