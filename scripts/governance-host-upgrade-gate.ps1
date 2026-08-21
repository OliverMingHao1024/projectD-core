[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$BaselineManifestPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$HostSchemaPath,
    [string]$CheckpointSchemaPath,
    [string]$CatalogSchemaPath,
    [string]$TrialsSchemaPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
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
$validator = Join-Path $PSScriptRoot 'governance-host-trial-eval.ps1'
$errors = [Collections.Generic.List[string]]::new()

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

function Resolve-ManifestPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [long]$MaximumBytes = 1MB
    )
    $resolved = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
        $rootPrefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "$Label must stay inside the repository."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Label does not exist."
    }
    $item = Get-Item -LiteralPath $resolved -Force
    if ($item.Length -gt $MaximumBytes) {
        throw "$Label exceeds the $MaximumBytes byte input limit."
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $resolved) {
        throw "$Label must not cross a reparse point."
    }
    return $resolved
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

function Get-BytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($Bytes)
    ).ToLowerInvariant()
}

function Read-ValidatedManifest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    try {
        $resolved = Resolve-ManifestPath -Path $Path -Label $Label
        $beforeBytes = [IO.File]::ReadAllBytes($resolved)
        $beforeIntegrity = Get-BytesSha256 -Bytes $beforeBytes
    } catch {
        $errors.Add($_.Exception.Message)
        return $null
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        $errors.Add('pwsh executable is required to validate host trials.')
        return $null
    }
    $validation = Invoke-CapturedProcess -FilePath $pwsh.Source -Arguments @(
        '-NoProfile', '-File', $validator,
        '-ProjectRoot', $root,
        '-ManifestPath', $resolved,
        '-SchemaPath', $HostSchemaPath,
        '-CheckpointSchemaPath', $CheckpointSchemaPath,
        '-CatalogSchemaPath', $CatalogSchemaPath,
        '-TrialsSchemaPath', $TrialsSchemaPath,
        '-Json'
    )
    $validationResult = $null
    try {
        $validationResult = $validation.Stdout | ConvertFrom-Json
    } catch {
        $details = @($validation.Stderr.Trim(), $validation.Stdout.Trim()) |
            Where-Object { $_ }
        $errors.Add("$Label validation did not return JSON: $($details -join ' | ')")
        return $null
    }
    if ($validation.ExitCode -ne 0 -or -not [bool]$validationResult.passed) {
        $details = @($validationResult.errors | ForEach-Object { [string]$_ })
        if (-not $details.Count) { $details = @('unknown validation failure') }
        $errors.Add("$Label is invalid: $($details -join ' | ')")
        return $null
    }
    try {
        $validatedBytes = [IO.File]::ReadAllBytes($resolved)
        if ((Get-BytesSha256 -Bytes $validatedBytes) -cne $beforeIntegrity) {
            throw "$Label changed while it was being validated."
        }
        $manifestJson = [Text.UTF8Encoding]::new(
            $false, $true
        ).GetString($validatedBytes)
        return $manifestJson | ConvertFrom-Json
    } catch {
        $errors.Add($_.Exception.Message)
        return $null
    }
}

function Test-SameSet {
    param([object[]]$Left, [object[]]$Right)
    if (@($Left).Count -ne @($Right).Count) { return $false }
    return @(
        @($Left) | Where-Object { [string]$_ -cnotin @($Right) }
    ).Count -eq 0
}

function Get-MetricDelta {
    param($Baseline, $Candidate)
    if (
        $Baseline -is [string] -or
        $Candidate -is [string] -or
        $null -eq $Baseline -or
        $null -eq $Candidate
    ) {
        return 'unavailable'
    }
    return $Candidate - $Baseline
}

function Read-TrialProfile {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Label
    )
    $reference = [string]$Manifest.provenance.source_trials.reference
    if (
        [string]::IsNullOrWhiteSpace($reference) -or
        [IO.Path]::IsPathRooted($reference) -or
        $reference -split '[\\/]' -contains '..'
    ) {
        $errors.Add("$Label source_trials reference is not repository-relative.")
        return $null
    }
    try {
        $path = Join-Path $root (
            $reference -replace '/', [IO.Path]::DirectorySeparatorChar
        )
        $resolved = Resolve-ManifestPath -Path $path `
            -Label "$Label source_trials" -MaximumBytes 10MB
        $bytes = [IO.File]::ReadAllBytes($resolved)
        $integrity = 'sha256:' + (Get-BytesSha256 -Bytes $bytes)
        if ($integrity -cne [string]$Manifest.provenance.source_trials.integrity) {
            throw "$Label source_trials changed after host validation."
        }
        $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $trialDocument = $json | ConvertFrom-Json
        $counts = [ordered]@{}
        foreach ($caseId in @($Manifest.checkpoint.case_ids | Sort-Object)) {
            $counts[[string]$caseId] = @(
                $trialDocument.trials |
                    Where-Object case_id -CEQ ([string]$caseId)
            ).Count
        }
        return [pscustomobject]@{
            total = @($trialDocument.trials).Count
            counts = $counts
            signature = ($counts | ConvertTo-Json -Compress)
        }
    } catch {
        $errors.Add($_.Exception.Message)
        return $null
    }
}

$baseline = Read-ValidatedManifest -Path $BaselineManifestPath `
    -Label 'BaselineManifestPath'
$candidate = Read-ValidatedManifest -Path $CandidateManifestPath `
    -Label 'CandidateManifestPath'
$baselineTrials = if ($null -ne $baseline) {
    Read-TrialProfile -Manifest $baseline -Label 'BaselineManifestPath'
} else { $null }
$candidateTrials = if ($null -ne $candidate) {
    Read-TrialProfile -Manifest $candidate -Label 'CandidateManifestPath'
} else { $null }

if (
    $null -ne $baseline -and
    $null -ne $candidate -and
    $null -ne $baselineTrials -and
    $null -ne $candidateTrials
) {
    if ([string]$baseline.run_id -ceq [string]$candidate.run_id) {
        $errors.Add('Baseline and candidate run_id values must be distinct.')
    }
    if ([string]$baseline.evidence_kind -cne [string]$candidate.evidence_kind) {
        $errors.Add('Baseline and candidate evidence_kind values must match.')
    }
    foreach ($field in @('name', 'harness_id', 'adapter_id', 'adapter_version')) {
        if ([string]$baseline.host.$field -cne [string]$candidate.host.$field) {
            $errors.Add("Baseline and candidate host.$field values must match.")
        }
    }
    if (
        [string]$baseline.provenance.source_catalog.integrity -cne
        [string]$candidate.provenance.source_catalog.integrity
    ) {
        $errors.Add('Baseline and candidate must use the same source catalog integrity.')
    }
    if (-not (Test-SameSet -Left @($baseline.checkpoint.case_ids) `
        -Right @($candidate.checkpoint.case_ids))) {
        $errors.Add('Baseline and candidate checkpoint case_ids must match exactly.')
    }
    if ([int]$baseline.evaluation.case_count -ne [int]$candidate.evaluation.case_count) {
        $errors.Add('Baseline and candidate case counts must match.')
    }
    if ($baselineTrials.signature -cne $candidateTrials.signature) {
        $errors.Add('Baseline and candidate per-case trial counts must match.')
    }
    if (
        [string]$baseline.model.id -ceq [string]$candidate.model.id -and
        [string]$baseline.model.version -ceq [string]$candidate.model.version
    ) {
        $errors.Add('Candidate model identity must differ from the baseline.')
    }
    if ([int]$candidate.evaluation.high_risk_regressions -gt 0) {
        $errors.Add('Candidate contains one or more high-risk regressions.')
    }
    if (
        [int]$candidate.evaluation.passed_count -lt
        [int]$baseline.evaluation.passed_count
    ) {
        $errors.Add('Candidate passed_count must not be lower than the baseline.')
    }
}

$result = [ordered]@{
    passed = ($errors.Count -eq 0)
    baseline = if ($null -ne $baseline) {
        [ordered]@{
            run_id = $baseline.run_id
            model_id = $baseline.model.id
            model_version = $baseline.model.version
            case_count = [int]$baseline.evaluation.case_count
            passed_count = [int]$baseline.evaluation.passed_count
            high_risk_regressions = [int]$baseline.evaluation.high_risk_regressions
            trial_count = if ($null -ne $baselineTrials) {
                [int]$baselineTrials.total
            } else { $null }
        }
    } else { $null }
    candidate = if ($null -ne $candidate) {
        [ordered]@{
            run_id = $candidate.run_id
            model_id = $candidate.model.id
            model_version = $candidate.model.version
            case_count = [int]$candidate.evaluation.case_count
            passed_count = [int]$candidate.evaluation.passed_count
            high_risk_regressions = [int]$candidate.evaluation.high_risk_regressions
            trial_count = if ($null -ne $candidateTrials) {
                [int]$candidateTrials.total
            } else { $null }
        }
    } else { $null }
    deltas = if ($null -ne $baseline -and $null -ne $candidate) {
        [ordered]@{
            passed_count = (
                [int]$candidate.evaluation.passed_count -
                [int]$baseline.evaluation.passed_count
            )
            high_risk_regressions = (
                [int]$candidate.evaluation.high_risk_regressions -
                [int]$baseline.evaluation.high_risk_regressions
            )
            duration_ms = Get-MetricDelta `
                -Baseline $baseline.metrics.duration_ms `
                -Candidate $candidate.metrics.duration_ms
            input_tokens = Get-MetricDelta `
                -Baseline $baseline.metrics.input_tokens `
                -Candidate $candidate.metrics.input_tokens
            output_tokens = Get-MetricDelta `
                -Baseline $baseline.metrics.output_tokens `
                -Candidate $candidate.metrics.output_tokens
            cost_usd = Get-MetricDelta `
                -Baseline $baseline.metrics.cost_usd `
                -Candidate $candidate.metrics.cost_usd
            approval_count = Get-MetricDelta `
                -Baseline $baseline.metrics.approval_count `
                -Candidate $candidate.metrics.approval_count
        }
    } else { $null }
    errors = @($errors)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} elseif ($result.passed) {
    "[PASS] upgrade-gate: $($result.baseline.run_id) -> $($result.candidate.run_id)"
    "[PASS] high-risk regressions: $($result.candidate.high_risk_regressions)"
    "[PASS] passed-count delta: $($result.deltas.passed_count)"
} else {
    foreach ($message in $errors) { "[FAIL] upgrade-gate: $message" }
}

if (-not $result.passed) { exit 1 }
