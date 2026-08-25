[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('codex', 'claude')]
    [string]$HostName = 'codex',
    [Parameter(Mandatory)][string]$TrialsPath,
    [string]$CatalogPath,
    [string]$CatalogSchemaPath,
    [string]$TrialsSchemaPath,
    [string]$HostSchemaPath,
    [string]$CheckpointSchemaPath,
    [string]$OutputPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ModelId,
    [Parameter(Mandatory)][string]$ModelVersion,
    [string]$HarnessId = 'codex-manual-import-v1',
    [Parameter(Mandatory)][string]$StartedAt,
    [Parameter(Mandatory)][string]$CompletedAt,
    [string]$InputTokens = 'unavailable',
    [string]$OutputTokens = 'unavailable',
    [string]$CostUsd = 'unavailable',
    [Parameter(Mandatory)][int]$ApprovalCount,
    [Parameter(Mandatory)][string[]]$CompletedCriterion,
    [Parameter(Mandatory)][string[]]$RemainingCriterion,
    [Parameter(Mandatory)][string]$SmokeTestId,
    [Parameter(Mandatory)]
    [ValidateSet('passed', 'failed', 'not-run')]
    [string]$SmokeTestStatus,
    [switch]$CheckpointRead,
    [switch]$WorkspaceVerified,
    [switch]$AuthorizedManualImport,
    [switch]$ContractFixture,
    [Alias('CodexVersionOverride')]
    [string]$CliVersionOverride,
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
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root ".local\governance\$RunId.json"
}
$behaviorRunner = Join-Path $PSScriptRoot 'governance-behavior-eval.ps1'
$hostValidator = Join-Path $PSScriptRoot 'governance-host-trial-eval.ps1'

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
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
        Stdout = $stdout
        Stderr = if ($timedOut) {
            "Process timed out after 30000 ms. $stderr".Trim()
        } else { $stderr }
    }
}

function Convert-CountMetric {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Name)
    if ($Value -ceq 'unavailable') { return 'unavailable' }
    $parsed = 0L
    if (-not [long]::TryParse($Value, [ref]$parsed) -or $parsed -lt 0) {
        throw "$Name must be a non-negative integer or unavailable."
    }
    return $parsed
}

function Convert-CostMetric {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -ceq 'unavailable') { return 'unavailable' }
    $parsed = 0.0
    if (-not [double]::TryParse(
        $Value,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    ) -or $parsed -lt 0) {
        throw 'CostUsd must be a non-negative number or unavailable.'
    }
    return $parsed
}

if ($AuthorizedManualImport -eq $ContractFixture) {
    throw 'Choose exactly one of AuthorizedManualImport or ContractFixture.'
}
if ($ContractFixture -and [string]::IsNullOrWhiteSpace($CliVersionOverride)) {
    throw 'ContractFixture requires CliVersionOverride.'
}
if ($AuthorizedManualImport -and -not [string]::IsNullOrWhiteSpace(
    $CliVersionOverride
)) {
    throw 'Live capture cannot override the detected host CLI version.'
}
foreach ($value in @($RunId, $HarnessId, $SmokeTestId) +
    @($CompletedCriterion) + @($RemainingCriterion)) {
    if ([string]$value -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Invalid slug value: $value"
    }
}
foreach ($value in @($ModelId, $ModelVersion)) {
    if ([string]$value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid model identity value: $value"
    }
}
if ($ApprovalCount -lt 0) { throw 'ApprovalCount must be non-negative.' }

$started = [DateTimeOffset]::Parse(
    $StartedAt, [Globalization.CultureInfo]::InvariantCulture
)
$completed = [DateTimeOffset]::Parse(
    $CompletedAt, [Globalization.CultureInfo]::InvariantCulture
)
if ($completed -lt $started) { throw 'CompletedAt must not precede StartedAt.' }

$trialsFullPath = Resolve-RepositoryPath `
    -Root $root -Path $TrialsPath -Label 'TrialsPath' -MaximumBytes 10MB
$catalogFullPath = Resolve-RepositoryPath `
    -Root $root -Path $CatalogPath -Label 'CatalogPath' -MaximumBytes 10MB
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
$allowedOutputRoot = [IO.Path]::GetFullPath((Join-Path $root '.local\governance'))
$allowedOutputPrefix = $allowedOutputRoot.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
) + [IO.Path]::DirectorySeparatorChar
if (-not $outputFullPath.StartsWith(
    $allowedOutputPrefix, [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'OutputPath must stay under .local/governance.'
}
if (Test-Path -LiteralPath $outputFullPath) {
    throw 'OutputPath already exists; choose a new run id or remove it explicitly.'
}
if (Test-PathHasReparsePoint -Root $root -ResolvedPath $outputFullPath) {
    throw 'OutputPath must not cross a reparse point.'
}

$pwsh = Get-Command pwsh -ErrorAction Stop
$evaluation = Invoke-CapturedProcess -FilePath $pwsh.Source -Arguments @(
    '-NoProfile', '-File', $behaviorRunner,
    '-ProjectRoot', $root,
    '-CatalogPath', $catalogFullPath,
    '-CatalogSchemaPath', $CatalogSchemaPath,
    '-TrialsPath', $trialsFullPath,
    '-TrialsSchemaPath', $TrialsSchemaPath,
    '-Json'
)
try {
    $behaviorResult = $evaluation.Stdout | ConvertFrom-Json
} catch {
    $details = @($evaluation.Stdout.Trim(), $evaluation.Stderr.Trim()) |
        Where-Object { $_ }
    throw "Source trials did not produce a behavior result: $($details -join ' | ')"
}
if (
    $evaluation.ExitCode -notin @(0, 1) -or
    ($evaluation.ExitCode -eq 0) -ne [bool]$behaviorResult.passed
) {
    throw 'Behavior evaluator exit status does not match its structured result.'
}

$catalog = Get-Content -Raw -LiteralPath $catalogFullPath | ConvertFrom-Json
$trials = Get-Content -Raw -LiteralPath $trialsFullPath | ConvertFrom-Json
foreach ($trial in @($trials.trials)) {
    if (
        [string]$trial.agent -cne $HostName -or
        [string]$trial.model -cne $ModelId -or
        [string]$trial.harness -cne $HarnessId
    ) {
        throw "$($trial.trial_id) does not match the supplied $HostName identity."
    }
}

$hostCliVersion = if ($ContractFixture) {
    $CliVersionOverride.Trim()
} else {
    $hostCli = Get-Command $HostName -ErrorAction Stop
    $versionResult = Invoke-CapturedProcess `
        -FilePath $hostCli.Source -Arguments @('--version')
    if ($versionResult.ExitCode -ne 0) {
        throw "$HostName version detection failed."
    }
    $versionResult.Stdout.Trim()
}
if ($hostCliVersion -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._ -]{0,127}$') {
    throw "Detected $HostName version contains unsupported characters."
}

$git = Get-Command git -ErrorAction Stop
$commitResult = Invoke-CapturedProcess -FilePath $git.Source -Arguments @(
    '-C', $root, 'rev-parse', 'HEAD'
)
if ($commitResult.ExitCode -ne 0) { throw 'ProjectRoot must be a Git repository.' }
$commit = $commitResult.Stdout.Trim()
if ($commit -cnotmatch '^[A-Fa-f0-9]{40}$') {
    throw 'Git HEAD did not resolve to a full commit id.'
}
$statusResult = Invoke-CapturedProcess -FilePath $git.Source -Arguments @(
    '-C', $root, 'status', '--porcelain=v1', '--untracked-files=no'
)
if ($statusResult.ExitCode -ne 0) { throw 'Git workspace state could not be read.' }
$statusText = $statusResult.Stdout.TrimEnd("`r", "`n")
$workspaceState = if ($statusText) { 'modified' } else { 'clean' }
$workspaceIntegrity = Get-TextSha256 -Text $statusText

$caseChecks = @($behaviorResult.checks | Where-Object id -CNE 'catalog')
$passedCount = @($caseChecks | Where-Object passed).Count
$highRiskCaseIds = @(
    $catalog.cases |
        Where-Object { $_.risk_tier -in @('high', 'critical') } |
        ForEach-Object id
)
$highRiskRegressions = @(
    $caseChecks |
        Where-Object { -not $_.passed -and $_.id -cin $highRiskCaseIds }
).Count
$recoveryCasePassed = @(
    $caseChecks |
        Where-Object {
            $_.id -ceq 'interrupted-task-reads-checkpoint-before-resume' -and
            $_.passed
        }
).Count -eq 1
$safeToResume = (
    [bool]$behaviorResult.passed -and
    $recoveryCasePassed -and
    $CheckpointRead.IsPresent -and
    $WorkspaceVerified.IsPresent -and
    $SmokeTestStatus -ceq 'passed'
)
$document = [ordered]@{
    schema_version = 1
    run_id = $RunId
    evidence_kind = if ($ContractFixture) {
        'contract-fixture'
    } else { 'manual-authorized-import' }
    host = [ordered]@{
        name = $HostName
        cli_version = $hostCliVersion
        harness_id = $HarnessId
        adapter_id = "$HostName-governance-adapter"
        adapter_version = 1
    }
    model = [ordered]@{
        id = $ModelId
        version = $ModelVersion
        version_evidence = if ($ContractFixture) {
            'contract-fixture'
        } else { 'user-supplied' }
    }
    started_at = $started.ToUniversalTime().ToString('o')
    completed_at = $completed.ToUniversalTime().ToString('o')
    provenance = [ordered]@{
        authorization = if ($ContractFixture) {
            'contract-fixture'
        } else { 'explicit-current-task' }
        import_transport = 'structured-json'
        model_execution_attested = $AuthorizedManualImport.IsPresent
        source_trials = [ordered]@{
            reference = Get-RepositoryReference -Root $root -Path $trialsFullPath
            integrity = Get-FileSha256 -Path $trialsFullPath
        }
        source_catalog = [ordered]@{
            reference = Get-RepositoryReference -Root $root -Path $catalogFullPath
            integrity = Get-FileSha256 -Path $catalogFullPath
        }
    }
    privacy = [ordered]@{
        content_mode = 'metadata-only'
        redaction_status = 'verified'
        contains_raw_prompt = $false
        contains_chain_of_thought = $false
        contains_secret_values = $false
        contains_private_data = $false
    }
    metrics = [ordered]@{
        duration_ms = [long][Math]::Round(($completed - $started).TotalMilliseconds)
        input_tokens = Convert-CountMetric -Value $InputTokens -Name 'InputTokens'
        output_tokens = Convert-CountMetric -Value $OutputTokens -Name 'OutputTokens'
        cost_usd = Convert-CostMetric -Value $CostUsd
        approval_count = $ApprovalCount
    }
    evaluation = [ordered]@{
        passed = [bool]$behaviorResult.passed
        case_count = [int]$behaviorResult.evaluated
        passed_count = $passedCount
        high_risk_regressions = $highRiskRegressions
    }
    checkpoint = [ordered]@{
        checkpoint_id = "$RunId-checkpoint"
        task_ref = $RunId
        case_ids = @($catalog.cases.id)
        created_at = $completed.ToUniversalTime().ToString('o')
        repository = [ordered]@{
            reference = 'repository-root'
            commit = $commit
            workspace_state = $workspaceState
            state_integrity = $workspaceIntegrity
        }
        acceptance = [ordered]@{
            completed = @($CompletedCriterion)
            remaining = @($RemainingCriterion)
        }
        recovery = [ordered]@{
            checkpoint_read = $CheckpointRead.IsPresent
            workspace_verified = $WorkspaceVerified.IsPresent
            smoke_test = [ordered]@{
                id = $SmokeTestId
                status = $SmokeTestStatus
                evidence_code = "smoke-test-$SmokeTestStatus"
            }
            safe_to_resume = $safeToResume
        }
    }
}

$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$document | ConvertTo-Json -Depth 30 |
    Set-Content -LiteralPath $outputFullPath -Encoding utf8 -NoNewline

$validation = Invoke-CapturedProcess -FilePath $pwsh.Source -Arguments @(
    '-NoProfile', '-File', $hostValidator,
    '-ProjectRoot', $root,
    '-ManifestPath', $outputFullPath,
    '-SchemaPath', $HostSchemaPath,
    '-CheckpointSchemaPath', $CheckpointSchemaPath,
    '-CatalogSchemaPath', $CatalogSchemaPath,
    '-TrialsSchemaPath', $TrialsSchemaPath,
    '-VerifyCurrentWorkspace',
    '-Json'
)
if ($validation.ExitCode -ne 0) {
    Remove-Item -LiteralPath $outputFullPath -Force
    $details = @(
        $validation.Stdout.Trim(),
        $validation.Stderr.Trim()
    ) | Where-Object { $_ }
    throw "Generated host-trial manifest failed validation: $($details -join ' | ')"
}
$validationResult = $validation.Stdout | ConvertFrom-Json
$result = [pscustomobject]@{
    passed = [bool]$validationResult.passed
    run_id = $RunId
    output = Get-RepositoryReference -Root $root -Path $outputFullPath
    evidence_kind = $document.evidence_kind
    case_count = [int]$behaviorResult.evaluated
    trial_passed = [bool]$behaviorResult.passed
    recovery_case_passed = $recoveryCasePassed
    safe_to_resume = $safeToResume
}
if ($Json) {
    $result | ConvertTo-Json -Depth 6
} else {
    "[PASS] $HostName host-trial manifest: $($result.output)"
    "[PASS] behavior-cases: $($result.case_count) evaluated; trial_passed=$($result.trial_passed)"
    "[PASS] checkpoint: safe_to_resume=$($result.safe_to_resume)"
}
