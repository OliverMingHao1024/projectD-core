[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ManifestPath,
    [string]$SchemaPath,
    [string]$CheckpointSchemaPath,
    [string]$CatalogSchemaPath,
    [string]$TrialsSchemaPath,
    [switch]$VerifyCurrentWorkspace,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $root '.local\governance\host-trial.json'
}
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path $root 'evals\schemas\governance-host-trials.schema.json'
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
$behaviorRunner = Join-Path $PSScriptRoot 'governance-behavior-eval.ps1'

function Find-ForbiddenField {
    param($Value, [string]$Path = '$')
    $forbidden = @(
        'prompt', 'raw_prompt', 'chain_of_thought', 'reasoning', 'secret',
        'token', 'password', 'credential_value', 'private_data', 'payload',
        'arguments', 'stdout', 'stderr'
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

function Find-SensitiveValue {
    param($Value, [string]$Path = '$')
    if ($null -eq $Value) { return @() }
    $hits = @()
    if ($Value -is [string]) {
        foreach ($pattern in @(
            '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
            '\bgh[pousr]_[A-Za-z0-9]{20,}\b',
            '\bgithub_pat_[A-Za-z0-9_]{20,}\b',
            '\bsk-[A-Za-z0-9_-]{20,}\b',
            '\bAKIA[0-9A-Z]{16}\b',
            '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}'
        )) {
            if ($Value -match $pattern) {
                $hits += $Path
                break
            }
        }
    } elseif (
        $Value -is [Collections.IDictionary] -or
        $Value -is [pscustomobject]
    ) {
        foreach ($property in $Value.PSObject.Properties) {
            $hits += @(Find-SensitiveValue $property.Value "$Path.$($property.Name)")
        }
    } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in $Value) {
            $hits += @(Find-SensitiveValue $item "$Path[$index]")
            $index++
        }
    }
    return $hits
}

function Test-PathHasReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ResolvedPath
    )
    $rootItem = Get-Item -LiteralPath $Root -Force
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        return $true
    }
    $relative = $ResolvedPath.Substring($Root.Length).TrimStart('\', '/')
    $current = $Root
    foreach ($part in @($relative -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                return $true
            }
        }
    }
    return $false
}

function Resolve-RepositoryFile {
    param(
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Collections.Generic.List[string]]$Errors,
        [long]$MaximumBytes = 10MB
    )
    if (
        [string]::IsNullOrWhiteSpace($Reference) -or
        [IO.Path]::IsPathRooted($Reference) -or
        $Reference -split '[\\/]' -contains '..'
    ) {
        $Errors.Add("$Label must be a repository-relative path without traversal.")
        return $null
    }
    $resolved = [IO.Path]::GetFullPath((
        Join-Path $root ($Reference -replace '/', [IO.Path]::DirectorySeparatorChar)
    ))
    $rootPrefix = $root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $Errors.Add("$Label resolves outside the repository.")
        return $null
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        $Errors.Add("$Label does not exist.")
        return $null
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $resolved) {
        $Errors.Add("$Label crosses a reparse point.")
        return $null
    }
    if ((Get-Item -LiteralPath $resolved -Force).Length -gt $MaximumBytes) {
        $Errors.Add("$Label exceeds the $MaximumBytes byte input limit.")
        return $null
    }
    return $resolved
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return 'sha256:' + [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))
    ).ToLowerInvariant()
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(
        ($Text -replace "\r\n?", "`n")
    )
    return 'sha256:' + [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

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

function Get-CurrentWorkspaceEvidence {
    param(
        [AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        $Errors.Add('git executable is required to verify checkpoint state.')
        return $null
    }
    $commitResult = Invoke-CapturedProcess -FilePath $git.Source -Arguments @(
        '-C', $root, 'rev-parse', 'HEAD'
    )
    if ($commitResult.ExitCode -ne 0) {
        $Errors.Add('Checkpoint repository commit could not be verified.')
        return $null
    }
    $statusResult = Invoke-CapturedProcess -FilePath $git.Source -Arguments @(
        '-C', $root, 'status', '--porcelain=v1', '--untracked-files=no'
    )
    if ($statusResult.ExitCode -ne 0) {
        $Errors.Add('Checkpoint workspace state could not be verified.')
        return $null
    }
    $statusText = $statusResult.Stdout.TrimEnd("`r", "`n")
    [pscustomobject]@{
        commit = $commitResult.Stdout.Trim()
        workspace_state = if ($statusText) { 'modified' } else { 'clean' }
        state_integrity = Get-TextSha256 -Text $statusText
    }
}

$errors = [Collections.Generic.List[string]]::new()
$document = $null
$behaviorResult = $null
$workspaceMatches = $null
$caseCount = 0
$safeToResume = $false
$recordedSafeToResume = $false
$recoveryCasePassed = $false

try {
    $manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
    $rootPrefix = $root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $manifestFullPath.StartsWith(
        $rootPrefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Host-trial manifest must stay inside the repository.'
    }
    $manifestItem = Get-Item -LiteralPath $manifestFullPath -Force
    if ($manifestItem.Length -gt 1MB) {
        throw 'Host-trial manifest exceeds the 1 MiB input limit.'
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $manifestItem.FullName) {
        throw 'Host-trial manifest must not cross a reparse point.'
    }
    $manifestJson = Get-Content -Raw -LiteralPath $manifestItem.FullName
    if (-not (
        Test-Json -Json $manifestJson -SchemaFile $SchemaPath -ErrorAction Stop
    )) {
        throw 'Host-trial manifest does not conform to its JSON Schema.'
    }
    $document = $manifestJson | ConvertFrom-Json
} catch {
    $errors.Add("Manifest parse failed: $($_.Exception.Message)")
}

if ($null -ne $document) {
    foreach ($field in @(Find-ForbiddenField $document)) {
        $errors.Add("Manifest contains forbidden sensitive field: $field")
    }
    foreach ($field in @(Find-SensitiveValue $document)) {
        $errors.Add("Manifest contains a secret-like value at: $field")
    }

    $checkpointJson = [pscustomobject]@{
        schema_version = 1
        checkpoint = $document.checkpoint
    } | ConvertTo-Json -Depth 20
    try {
        if (-not (
            Test-Json -Json $checkpointJson -SchemaFile $CheckpointSchemaPath `
                -ErrorAction Stop
        )) {
            throw 'Checkpoint does not conform to its JSON Schema.'
        }
    } catch {
        $errors.Add("Checkpoint validation failed: $($_.Exception.Message)")
    }

    $started = [DateTimeOffset]$document.started_at
    $completed = [DateTimeOffset]$document.completed_at
    if ($completed -lt $started) {
        $errors.Add('completed_at precedes started_at.')
    } else {
        $expectedDuration = [long][Math]::Round(
            ($completed - $started).TotalMilliseconds
        )
        if ([long]$document.metrics.duration_ms -ne $expectedDuration) {
            $errors.Add('duration_ms does not match the task timestamps.')
        }
    }

    if ($document.evidence_kind -eq 'contract-fixture') {
        if (
            $document.provenance.authorization -cne 'contract-fixture' -or
            $document.model.version_evidence -cne 'contract-fixture' -or
            [bool]$document.provenance.model_execution_attested
        ) {
            $errors.Add('Contract fixtures must not claim live model execution.')
        }
    } elseif (
        $document.provenance.authorization -cne 'explicit-current-task' -or
        $document.model.version_evidence -cne 'user-supplied' -or
        -not [bool]$document.provenance.model_execution_attested
    ) {
        $errors.Add(
            'Manual host imports require explicit authorization and user-attested execution.'
        )
    }

    $trialsPath = Resolve-RepositoryFile `
        -Reference ([string]$document.provenance.source_trials.reference) `
        -Label 'source_trials' -Errors $errors
    $catalogPath = Resolve-RepositoryFile `
        -Reference ([string]$document.provenance.source_catalog.reference) `
        -Label 'source_catalog' -Errors $errors

    if ($null -ne $trialsPath -and (
        (Get-FileSha256 -Path $trialsPath) -cne
        [string]$document.provenance.source_trials.integrity
    )) {
        $errors.Add('source_trials integrity does not match the referenced file.')
    }
    if ($null -ne $catalogPath -and (
        (Get-FileSha256 -Path $catalogPath) -cne
        [string]$document.provenance.source_catalog.integrity
    )) {
        $errors.Add('source_catalog integrity does not match the referenced file.')
    }

    if ($null -ne $trialsPath -and $null -ne $catalogPath) {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($null -eq $pwsh) {
            $errors.Add('pwsh executable is required to evaluate source trials.')
        } else {
            $evaluation = Invoke-CapturedProcess -FilePath $pwsh.Source -Arguments @(
                '-NoProfile', '-File', $behaviorRunner,
                '-ProjectRoot', $root,
                '-CatalogPath', $catalogPath,
                '-CatalogSchemaPath', $CatalogSchemaPath,
                '-TrialsPath', $trialsPath,
                '-TrialsSchemaPath', $TrialsSchemaPath,
                '-Json'
            )
            try {
                $behaviorResult = $evaluation.Stdout | ConvertFrom-Json
            } catch {
                $details = @($evaluation.Stdout.Trim(), $evaluation.Stderr.Trim()) |
                    Where-Object { $_ }
                $errors.Add(
                    "Behavior evaluator returned invalid JSON: $($details -join ' | ')"
                )
            }
            if (
                $null -ne $behaviorResult -and (
                    $evaluation.ExitCode -notin @(0, 1) -or
                    ($evaluation.ExitCode -eq 0) -ne
                        [bool]$behaviorResult.passed
                )
            ) {
                $errors.Add(
                    'Behavior evaluator exit status does not match its structured result.'
                )
            }
        }
    }

    if ($null -ne $behaviorResult) {
        $sourceContractFailures = @(
            $behaviorResult.checks | Where-Object {
                -not $_.passed -and
                $_.id -in @('catalog', 'trials') -and
                $_.PSObject.Properties.Name -notcontains 'trials'
            }
        )
        if ($sourceContractFailures.Count) {
            $errors.Add(
                'Source catalog or trials failed the behavior input contract.'
            )
        }
        $caseCount = [int]$behaviorResult.evaluated
        $caseChecks = @(
            $behaviorResult.checks | Where-Object id -CNE 'catalog'
        )
        $passedCount = @($caseChecks | Where-Object passed).Count
        if (
            [bool]$document.evaluation.passed -ne [bool]$behaviorResult.passed -or
            [int]$document.evaluation.case_count -ne $caseCount -or
            [int]$document.evaluation.passed_count -ne $passedCount
        ) {
            $errors.Add('Manifest evaluation summary does not match source trials.')
        }

        $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
        $trials = Get-Content -Raw -LiteralPath $trialsPath | ConvertFrom-Json
        $highRiskCaseIds = @(
            $catalog.cases |
                Where-Object { $_.risk_tier -in @('high', 'critical') } |
                ForEach-Object id
        )
        $highRiskRegressions = @(
            $caseChecks |
                Where-Object {
                    -not $_.passed -and $_.id -cin $highRiskCaseIds
                }
        ).Count
        $recoveryCasePassed = @(
            $caseChecks |
                Where-Object {
                    $_.id -ceq
                        'interrupted-task-reads-checkpoint-before-resume' -and
                    $_.passed
                }
        ).Count -eq 1
        if (
            [int]$document.evaluation.high_risk_regressions -ne
            $highRiskRegressions
        ) {
            $errors.Add('High-risk regression count does not match source trials.')
        }
        $catalogIds = @($catalog.cases.id)
        $checkpointIds = @($document.checkpoint.case_ids)
        if (
            @($catalogIds | Where-Object { $_ -cnotin $checkpointIds }).Count -gt 0 -or
            @($checkpointIds | Where-Object { $_ -cnotin $catalogIds }).Count -gt 0
        ) {
            $errors.Add('Checkpoint case_ids must exactly match the evaluated catalog.')
        }
        foreach ($trial in @($trials.trials)) {
            if (
                [string]$trial.agent -cne [string]$document.host.name -or
                [string]$trial.model -cne [string]$document.model.id -or
                [string]$trial.harness -cne [string]$document.host.harness_id
            ) {
                $errors.Add(
                    "$($trial.trial_id) identity does not match the host envelope."
                )
            }
        }
    }

    $completedCriteria = @($document.checkpoint.acceptance.completed)
    $remainingCriteria = @($document.checkpoint.acceptance.remaining)
    if (@($completedCriteria | Where-Object { $_ -cin $remainingCriteria }).Count) {
        $errors.Add('Checkpoint acceptance criteria cannot be both completed and remaining.')
    }
    $recordedSafeToResume = (
        [bool]$document.evaluation.passed -and
        $recoveryCasePassed -and
        [bool]$document.checkpoint.recovery.checkpoint_read -and
        [bool]$document.checkpoint.recovery.workspace_verified -and
        [string]$document.checkpoint.recovery.smoke_test.status -ceq 'passed'
    )
    if (
        [bool]$document.checkpoint.recovery.safe_to_resume -ne
        $recordedSafeToResume
    ) {
        $errors.Add('safe_to_resume does not match checkpoint verification evidence.')
    }
    $checkpointTime = [DateTimeOffset]$document.checkpoint.created_at
    if ($checkpointTime -lt $started -or $checkpointTime -gt $completed) {
        $errors.Add('Checkpoint created_at is outside the trial time bounds.')
    }

    if ($VerifyCurrentWorkspace) {
        $current = Get-CurrentWorkspaceEvidence -Errors $errors
        if ($null -ne $current) {
            $workspaceMatches = (
                [string]$current.commit -ceq
                    [string]$document.checkpoint.repository.commit -and
                [string]$current.workspace_state -ceq
                    [string]$document.checkpoint.repository.workspace_state -and
                [string]$current.state_integrity -ceq
                    [string]$document.checkpoint.repository.state_integrity
            )
            if (-not $workspaceMatches) {
                $errors.Add('Current workspace does not match the checkpoint evidence.')
            }
            $safeToResume = $recordedSafeToResume -and $workspaceMatches
        }
    }
}

$result = [pscustomobject]@{
    passed = ($errors.Count -eq 0)
    run_id = if ($null -ne $document) { $document.run_id } else { $null }
    evidence_kind = if ($null -ne $document) {
        $document.evidence_kind
    } else { $null }
    case_count = $caseCount
    recovery_case_passed = $recoveryCasePassed
    recorded_safe_to_resume = $recordedSafeToResume
    safe_to_resume = $safeToResume
    workspace_matches = $workspaceMatches
    errors = @($errors)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    if ($result.passed) {
        "[PASS] host-trial: $($result.run_id)"
        "[PASS] behavior-cases: $($result.case_count) evaluated"
        "[PASS] checkpoint: safe_to_resume=$($result.safe_to_resume)"
    } else {
        foreach ($message in $errors) { "[FAIL] host-trial: $message" }
    }
    "Summary: $(if ($result.passed) { '3 passed, 0 failed' } else { "0 passed, $($errors.Count) failed" })"
}

if (-not $result.passed) { exit 1 }
