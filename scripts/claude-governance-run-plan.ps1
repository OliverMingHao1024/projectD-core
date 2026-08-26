[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$PlanPath,
    [string]$SchemaPath,
    [string]$CatalogSchemaPath,
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $root (
        'evals\schemas\governance-host-run-plan.schema.json'
    )
}
if ([string]::IsNullOrWhiteSpace($CatalogSchemaPath)) {
    $CatalogSchemaPath = Join-Path $root (
        'evals\schemas\governance-behavior-cases.schema.json'
    )
}

function Read-SourceEvidence {
    param(
        [Parameter(Mandatory)]$Evidence,
        [Parameter(Mandatory)][string]$Label
    )
    $path = Resolve-RepositoryReference -Root $root `
        -Reference ([string]$Evidence.reference) -Label $Label -MaximumBytes 1MB
    $bytes = [IO.File]::ReadAllBytes($path)
    $integrity = 'sha256:' + [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
    if ($integrity -cne [string]$Evidence.integrity) {
        throw "$Label integrity does not match the referenced file."
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    } catch {
        throw "$Label must be valid UTF-8 text."
    }
    if (Test-ContainsSensitiveValue -Text $text) {
        throw "$Label contains a secret-like value."
    }
    return [pscustomobject]@{
        path = $path
        integrity = $integrity
        text = $text
    }
}

function Get-RequiredObservers {
    param([Parameter(Mandatory)]$Case)
    $required = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($property in @($Case.expect.final_state.PSObject.Properties.Name)) {
        $observer = switch ($property) {
            'workspace_modified' { 'git-status-v1' }
            'sibling_repository_modified' { 'filesystem-digest-v1' }
            'external_state_changed' { 'tool-event-ledger-v1' }
            'secrets_exposed' { 'tool-event-ledger-v1' }
            'dependencies_added' { 'filesystem-digest-v1' }
            'destructive_change' { 'filesystem-digest-v1' }
            'memory_promoted' { 'filesystem-digest-v1' }
            'regression_threshold_met' { 'paired-gate-v1' }
            'checkpoint_read' { 'tool-event-ledger-v1' }
            'smoke_test_passed' { 'smoke-test-v1' }
            'acceptance_criteria_met' { 'smoke-test-v1' }
            default {
                throw "No observer mapping exists for final-state field: $property"
            }
        }
        if ($observer) { [void]$required.Add($observer) }
    }
    if (@($Case.expect.required_events).Count -gt 0 -or
        @($Case.expect.forbidden_events).Count -gt 0 -or
        $null -ne $Case.expect.max_action_count) {
        [void]$required.Add('tool-event-ledger-v1')
    }
    if ($Case.expect.outcome.PSObject.Properties.Name -contains 'verification_passed') {
        [void]$required.Add('smoke-test-v1')
    }
    return @($required)
}

$errors = [Collections.Generic.List[string]]::new()
$document = $null
$catalog = $null
$maximumInvocations = 0
$projectedBudget = 0.0

try {
    $planFullPath = Resolve-RepositoryPath `
        -Root $root -Path $PlanPath -Label 'PlanPath' -MaximumBytes 1MB
    $planJson = Get-Content -Raw -LiteralPath $planFullPath
    if (-not (Test-Json -Json $planJson -SchemaFile $SchemaPath -ErrorAction Stop)) {
        throw 'Run plan does not conform to its JSON Schema.'
    }
    $document = $planJson | ConvertFrom-Json
} catch {
    $errors.Add("Run-plan parse failed: $($_.Exception.Message)")
}

if ($null -ne $document) {
    foreach ($model in @($document.models.baseline, $document.models.candidate)) {
        if ([string]$model.id -cin @('default', 'inherit', 'opus', 'sonnet', 'haiku')) {
            $errors.Add("Floating model alias is not allowed: $($model.id)")
        }
    }
    if (
        [string]$document.models.baseline.id -ceq
            [string]$document.models.candidate.id -and
        [string]$document.models.baseline.version -ceq
            [string]$document.models.candidate.version
    ) {
        $errors.Add('Baseline and candidate model identities must differ.')
    }

    try {
        $catalogSource = Read-SourceEvidence -Evidence $document.catalog `
            -Label 'catalog'
        if (-not (
            Test-Json -Json $catalogSource.text `
                -SchemaFile $CatalogSchemaPath -ErrorAction Stop
        )) {
            throw 'Catalog does not conform to its JSON Schema.'
        }
        $catalog = $catalogSource.text | ConvertFrom-Json
        [void](Read-SourceEvidence -Evidence $document.instruction `
            -Label 'instruction')
    } catch {
        $errors.Add($_.Exception.Message)
    }

    $caseIds = @($document.cases.case_id)
    if (($caseIds | Select-Object -Unique).Count -ne $caseIds.Count) {
        $errors.Add('Run-plan case_id values must be unique.')
    }
    if ($null -ne $catalog) {
        foreach ($plannedCase in @($document.cases)) {
            $catalogCase = @($catalog.cases | Where-Object {
                [string]$_.id -ceq [string]$plannedCase.case_id
            })
            if ($catalogCase.Count -ne 1) {
                $errors.Add("Unknown or duplicate catalog case: $($plannedCase.case_id)")
                continue
            }
            try {
                [void](Read-SourceEvidence -Evidence $plannedCase.fixture `
                    -Label "fixture $($plannedCase.case_id)")
            } catch {
                $errors.Add($_.Exception.Message)
            }
            $actualObservers = @($plannedCase.observers)
            try {
                $requiredObservers = @(Get-RequiredObservers -Case $catalogCase[0])
            } catch {
                $errors.Add("$($plannedCase.case_id): $($_.Exception.Message)")
                continue
            }
            foreach ($requiredObserver in $requiredObservers) {
                if ($requiredObserver -cnotin $actualObservers) {
                    $errors.Add(
                        "$($plannedCase.case_id) requires observer $requiredObserver."
                    )
                }
            }
        }
    }

    $maximumInvocations = 2 * @(
        $document.cases | ForEach-Object { [int]$_.trial_count }
    ).Count
    $projectedBudget = [Math]::Round(
        $maximumInvocations * [double]$document.controls.per_trial_max_usd,
        6
    )
    if ($projectedBudget -gt [double]$document.controls.total_max_usd) {
        $errors.Add(
            'total_max_usd is lower than the per-trial cap times maximum invocations.'
        )
    }
}

$result = [ordered]@{
    passed = ($errors.Count -eq 0)
    plan_id = if ($null -ne $document) { $document.plan_id } else { $null }
    host = if ($null -ne $document) { $document.host.name } else { $null }
    baseline_model = if ($null -ne $document) {
        $document.models.baseline.id
    } else { $null }
    candidate_model = if ($null -ne $document) {
        $document.models.candidate.id
    } else { $null }
    case_count = if ($null -ne $document) { @($document.cases).Count } else { 0 }
    maximum_invocations = $maximumInvocations
    projected_budget_usd = $projectedBudget
    billing_mode = if ($null -ne $document) {
        $document.controls.billing_mode
    } else { $null }
    additional_spend_allowed = if ($null -ne $document) {
        [bool]$document.controls.additional_spend_allowed
    } else { $null }
    on_subscription_limit = if ($null -ne $document) {
        $document.controls.on_subscription_limit
    } else { $null }
    live_execution = $false
    errors = @($errors)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} elseif ($result.passed) {
    "[PASS] Claude paired-pilot plan: $($result.plan_id)"
    "[PASS] cases: $($result.case_count); maximum invocations: $maximumInvocations"
    "[PASS] additional spend: USD $projectedBudget; limit behavior: $($result.on_subscription_limit)"
    '[PASS] validation only: no model was launched'
} else {
    foreach ($message in $errors) { "[FAIL] Claude run-plan: $message" }
}

if (-not $result.passed -and -not $NoExit) { exit 1 }
