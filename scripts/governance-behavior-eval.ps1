[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$CatalogPath,
    [string]$CatalogSchemaPath,
    [string]$TrialsPath,
    [string]$TrialsSchemaPath,
    [switch]$CatalogOnly,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $root 'evals\governance-behavior-cases.json'
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

function Test-HasProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)
    $null -ne $Value -and $Value.PSObject.Properties.Name -contains $Name
}

function Test-ScalarEqual {
    param($Actual, $Expected)
    if ($null -eq $Expected) { return $null -eq $Actual }
    if ($Expected -is [bool]) { return $Actual -is [bool] -and $Actual -eq $Expected }
    if ($Expected -is [ValueType]) { return $Actual -eq $Expected }
    return [string]$Actual -ceq [string]$Expected
}

function Test-ObjectMatch {
    param($Actual, $Expected)
    if ($null -eq $Actual -or $null -eq $Expected) { return $false }
    foreach ($property in $Expected.PSObject.Properties) {
        if (-not (Test-HasProperty $Actual $property.Name)) { return $false }
        if (-not (Test-ScalarEqual $Actual.($property.Name) $property.Value)) {
            return $false
        }
    }
    return $true
}

function Find-ForbiddenField {
    param($Value, [string]$Path = '$')
    $forbidden = @(
        'prompt', 'raw_prompt', 'chain_of_thought', 'reasoning',
        'secret', 'token', 'password', 'credential_value'
    )
    if ($null -eq $Value) { return @() }
    $hits = @()
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -in $forbidden) {
                $hits += "$Path.$($property.Name)"
            }
            $hits += @(Find-ForbiddenField $property.Value "$Path.$($property.Name)")
        }
    } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in $Value) {
            $hits += @(Find-ForbiddenField $item "$Path[$index]")
            $index++
        }
    }
    return $hits
}


$checks = @()
$catalogErrors = @()
$cases = @()
try {
    $catalogJson = Get-Content -Raw -LiteralPath $CatalogPath
    if (-not (
        Test-Json -Json $catalogJson -SchemaFile $CatalogSchemaPath `
            -ErrorAction Stop
    )) {
        throw 'Catalog does not conform to its JSON Schema.'
    }
    $catalog = $catalogJson | ConvertFrom-Json
    if ($catalog.schema_version -ne 1) {
        $catalogErrors += 'Unsupported catalog schema_version.'
    }
    $cases = @($catalog.cases)
    if ($cases.Count -eq 0) { $catalogErrors += 'Catalog must contain cases.' }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in $cases) {
        $id = [string]$case.id
        if ($id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or -not $ids.Add($id)) {
            $catalogErrors += "Invalid or duplicate case id: $id"
        }
        if ($case.suite -notin @('capability', 'regression', 'adversarial')) {
            $catalogErrors += "$id has an unsupported suite."
        }
        if ($case.risk_tier -notin @('low', 'medium', 'high', 'critical')) {
            $catalogErrors += "$id has an unsupported risk_tier."
        }
        if ([string]::IsNullOrWhiteSpace([string]$case.purpose)) {
            $catalogErrors += "$id must describe its purpose."
        }
        if ([int]$case.minimum_trials -lt 1) {
            $catalogErrors += "$id minimum_trials must be at least one."
        }
        $threshold = [double]$case.pass_threshold
        if ($threshold -lt 0 -or $threshold -gt 1) {
            $catalogErrors += "$id pass_threshold must be between zero and one."
        }
        if (-not (Test-HasProperty $case 'expect')) {
            $catalogErrors += "$id must define expectations."
        }
    }
    foreach ($field in @(Find-ForbiddenField $catalog)) {
        $catalogErrors += "Catalog contains forbidden sensitive field: $field"
    }
    foreach ($field in @(Find-SensitiveValue $catalog)) {
        $catalogErrors += "Catalog contains a secret-like value at: $field"
    }
} catch {
    $catalogErrors += "Catalog parse failed: $($_.Exception.Message)"
}

if ($catalogErrors.Count -gt 0) {
    $checks += [pscustomobject]@{
        id = 'catalog'; passed = $false; message = $catalogErrors -join '; '
    }
} else {
    $checks += [pscustomobject]@{
        id = 'catalog'; passed = $true
        message = "$($cases.Count) behavior case(s) valid"
    }
}

if (-not $CatalogOnly -and $catalogErrors.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($TrialsPath)) {
        $checks += [pscustomobject]@{
            id = 'trials'; passed = $false
            message = 'TrialsPath is required unless CatalogOnly is used.'
        }
    } else {
        try {
            $trialsJson = Get-Content -Raw -LiteralPath $TrialsPath
            if (-not (
                Test-Json -Json $trialsJson -SchemaFile $TrialsSchemaPath `
                    -ErrorAction Stop
            )) {
                throw 'Trials do not conform to their JSON Schema.'
            }
            $trialDocument = $trialsJson | ConvertFrom-Json
            $trialErrors = @()
            if ($trialDocument.schema_version -ne 1) {
                $trialErrors += 'Unsupported trial schema_version.'
            }
            foreach ($field in @(Find-ForbiddenField $trialDocument)) {
                $trialErrors += "Trials contain forbidden sensitive field: $field"
            }
            foreach ($field in @(Find-SensitiveValue $trialDocument)) {
                $trialErrors += "Trials contain a secret-like value at: $field"
            }
            $trials = @($trialDocument.trials)
            if ($trials.Count -eq 0) { $trialErrors += 'Trials must not be empty.' }
            $trialIds = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::Ordinal
            )
            $caseMap = @{}
            foreach ($case in $cases) { $caseMap[[string]$case.id] = $case }
            foreach ($trial in $trials) {
                $trialId = [string]$trial.trial_id
                if (
                    [string]::IsNullOrWhiteSpace($trialId) -or
                    -not $trialIds.Add($trialId)
                ) {
                    $trialErrors += "Invalid or duplicate trial_id: $trialId"
                }
                if (-not $caseMap.ContainsKey([string]$trial.case_id)) {
                    $trialErrors += "$trialId references an unknown case_id."
                }
                foreach ($field in @('agent', 'model', 'harness')) {
                    if ([string]::IsNullOrWhiteSpace([string]$trial.$field)) {
                        $trialErrors += "$trialId must identify $field."
                    }
                }
                if (-not (Test-HasProperty $trial 'events')) {
                    $trialErrors += "$trialId must contain events."
                }
                if (-not (Test-HasProperty $trial 'outcome')) {
                    $trialErrors += "$trialId must contain outcome."
                }
                if (-not (Test-HasProperty $trial 'final_state')) {
                    $trialErrors += "$trialId must contain final_state."
                }
            }
            if ($trialErrors.Count -gt 0) {
                $checks += [pscustomobject]@{
                    id = 'trials'; passed = $false
                    message = $trialErrors -join '; '
                }
            } else {
                foreach ($case in $cases) {
                    $caseTrials = @(
                        $trials | Where-Object case_id -CEQ ([string]$case.id)
                    )
                    $trialResults = @()
                    foreach ($trial in $caseTrials) {
                        $failures = @()
                        $expect = $case.expect
                        if (
                            (Test-HasProperty $expect 'outcome') -and
                            -not (Test-ObjectMatch $trial.outcome $expect.outcome)
                        ) {
                            $failures += 'outcome mismatch'
                        }
                        if (
                            (Test-HasProperty $expect 'final_state') -and
                            -not (
                                Test-ObjectMatch $trial.final_state `
                                    $expect.final_state
                            )
                        ) {
                            $failures += 'final_state mismatch'
                        }
                        foreach ($matcher in @($expect.required_events)) {
                            $matched = @(
                                @($trial.events) |
                                    Where-Object { Test-ObjectMatch $_ $matcher }
                            ).Count -gt 0
                            if (-not $matched) {
                                $failures += 'required event missing'
                            }
                        }
                        foreach ($matcher in @($expect.forbidden_events)) {
                            $matched = @(
                                @($trial.events) |
                                    Where-Object { Test-ObjectMatch $_ $matcher }
                            ).Count -gt 0
                            if ($matched) { $failures += 'forbidden event observed' }
                        }
                        if (Test-HasProperty $expect 'max_action_count') {
                            $actionCount = @(
                                @($trial.events) |
                                    Where-Object classification -CEQ 'action'
                            ).Count
                            if ($actionCount -gt [int]$expect.max_action_count) {
                                $failures += 'action budget exceeded'
                            }
                        }
                        $trialResults += [pscustomobject]@{
                            trial_id = $trial.trial_id
                            passed = ($failures.Count -eq 0)
                            message = if ($failures.Count) {
                                $failures -join ', '
                            } else { 'Trial matched observable expectations' }
                        }
                    }
                    $passedTrials = @($trialResults | Where-Object passed).Count
                    $enoughTrials = $caseTrials.Count -ge [int]$case.minimum_trials
                    $passRate = if ($caseTrials.Count) {
                        $passedTrials / $caseTrials.Count
                    } else { 0.0 }
                    $casePassed = $enoughTrials -and (
                        $passRate -ge [double]$case.pass_threshold
                    )
                    $checks += [pscustomobject]@{
                        id = $case.id
                        passed = $casePassed
                        message = (
                            "$passedTrials/$($caseTrials.Count) trials passed; " +
                            "minimum=$($case.minimum_trials); " +
                            "threshold=$($case.pass_threshold)"
                        )
                        trials = $trialResults
                    }
                }
            }
        } catch {
            $checks += [pscustomobject]@{
                id = 'trials'; passed = $false
                message = "Trial evaluation failed: $($_.Exception.Message)"
            }
        }
    }
}

$failed = @($checks | Where-Object { -not $_.passed })
$result = [pscustomobject]@{
    passed = ($failed.Count -eq 0)
    mode = if ($CatalogOnly) { 'catalog-only' } else { 'trial-evaluation' }
    evaluated = $cases.Count
    checks = $checks
}
if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    foreach ($check in $checks) {
        $state = if ($check.passed) { 'PASS' } else { 'FAIL' }
        "[$state] $($check.id): $($check.message)"
    }
    "Summary: $(@($checks | Where-Object passed).Count) passed, $($failed.Count) failed."
}
if ($failed.Count) { exit 1 }
