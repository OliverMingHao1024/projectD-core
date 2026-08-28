[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$FleetPath,
    [switch]$Json,
    [switch]$SkipFleet,
    [switch]$SkipGlobal,
    [switch]$SkipWiring,
    [switch]$GovernanceEvals
)

$ErrorActionPreference = 'Stop'
$core = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($FleetPath)) {
    $FleetPath = Join-Path $core 'fleet\fleet.json'
}
$results = @()
function Add-Result([string]$n,[bool]$p,[string]$m){$script:results+=,[pscustomobject]@{name=$n;passed=$p;message=$m}}

function Get-SkillCatalogCheck {
    param([Parameter(Mandatory)][string]$Core)

    $skillRoots = @(
        Join-Path $Core 'core\skills'
        Join-Path $Core 'packs'
    )
    $skills = @(
        foreach ($root in $skillRoots) {
            Get-ChildItem -LiteralPath $root -Directory |
                Where-Object Name -NotLike '_*'
        }
    )
    $coreSkillRoot = [IO.Path]::GetFullPath((Join-Path $Core 'core\skills'))
    $globalDiscoveryChars = 0
    $globalDiscoveryBudget = 6000
    $perSkillDiscoveryBudget = 260
    $bad = @()
    $duplicateNames = @(
        $skills | Group-Object Name | Where-Object Count -GT 1
    )
    foreach ($duplicate in $duplicateNames) {
        $bad += "$($duplicate.Name): duplicate canonical skill name"
    }
    foreach ($skillDirectory in $skills) {
        $skillPath = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            $bad += "$($skillDirectory.Name): missing SKILL.md"
            continue
        }
        if ($skillDirectory.Name -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            $bad += "$($skillDirectory.Name): invalid folder name"
        }
        $content = Get-Content -Raw -LiteralPath $skillPath
        $frontmatter = [regex]::Match(
            $content,
            '\A---\r?\n(?<yaml>.*?)\r?\n---(?:\r?\n|\z)',
            [Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $frontmatter.Success) {
            $bad += "$($skillDirectory.Name): invalid YAML frontmatter boundary"
            continue
        }
        $metadataLines = @(
            $frontmatter.Groups['yaml'].Value -split '\r?\n' |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $keys = @(
            $metadataLines |
                ForEach-Object {
                    if ($_ -match '^([a-zA-Z0-9_-]+):') { $Matches[1] }
                }
        )
        $unsupported = @($keys | Where-Object { $_ -notin @('name', 'description') })
        if ($unsupported.Count -gt 0) {
            $bad += "$($skillDirectory.Name): non-portable metadata $($unsupported -join ', ')"
        }
        $nameLines = @($metadataLines | Where-Object { $_ -match '^name:\s*(.+?)\s*$' })
        if (
            $nameLines.Count -ne 1 -or
            $nameLines[0] -cnotmatch (
                '^name:\s*' + [regex]::Escape($skillDirectory.Name) + '\s*$'
            )
        ) {
            $bad += "$($skillDirectory.Name): name must exactly match folder"
        }
        $descriptionLines = @(
            $metadataLines | Where-Object { $_ -match '^description:\s*(.+?)\s*$' }
        )
        if ($descriptionLines.Count -ne 1) {
            $bad += "$($skillDirectory.Name): description must be one non-empty line"
        } elseif (
            [IO.Path]::GetFullPath($skillDirectory.Parent.FullName) -ceq
                $coreSkillRoot
        ) {
            $description = [regex]::Match(
                $descriptionLines[0],
                '^description:\s*(.+?)\s*$'
            ).Groups[1].Value
            $catalogPath = [IO.Path]::GetRelativePath($Core, $skillPath)
            $perSkillChars = (
                $skillDirectory.Name.Length +
                $description.Length +
                $catalogPath.Length
            )
            if ($perSkillChars -gt $perSkillDiscoveryBudget) {
                $bad += (
                    "$($skillDirectory.Name): discovery metadata is " +
                    "$perSkillChars chars; per-skill budget is " +
                    "$perSkillDiscoveryBudget (trim the description)"
                )
            }
            $globalDiscoveryChars += $perSkillChars
        }
    }
    if ($globalDiscoveryChars -gt $globalDiscoveryBudget) {
        $bad += (
            "global Skill discovery metadata is $globalDiscoveryChars chars; " +
            "budget is $globalDiscoveryBudget"
        )
    }
    if ($bad.Count) {
        return [pscustomobject]@{
            name = 'skill-catalog'; passed = $false; message = ($bad -join '; ')
        }
    }
    $discoveryMessage = (
        "$($skills.Count) canonical skill(s) valid; global discovery " +
        "$globalDiscoveryChars/$globalDiscoveryBudget chars"
    )
    if ($globalDiscoveryChars -ge ($globalDiscoveryBudget * 0.8)) {
        $discoveryMessage += ' [WARN: at or above 80% of budget]'
    }
    return [pscustomobject]@{
        name = 'skill-catalog'
        passed = $true
        message = $discoveryMessage
    }
}

function Get-SkillRegistryCheck {
    param([Parameter(Mandatory)][string]$Core)

    $registryPath = Join-Path $Core 'vault\governance\skill-registry.json'
    $decisionPath = Join-Path $Core 'vault\governance\skill-candidates.md'
    $bad = @()
    $sources = @()
    $candidates = @()
    try {
        $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
        if ($registry.schema_version -ne 1) {
            $bad += 'unsupported schema_version'
        }
        $sources = @($registry.sources)
        $candidates = @($registry.candidates)
        foreach ($duplicate in @(
            $sources | Group-Object id | Where-Object Count -GT 1
        )) {
            $bad += "duplicate source id: $($duplicate.Name)"
        }
        foreach ($duplicate in @(
            $sources | Group-Object repository | Where-Object Count -GT 1
        )) {
            $bad += "duplicate repository: $($duplicate.Name)"
        }
        foreach ($duplicate in @(
            $candidates | Group-Object id | Where-Object Count -GT 1
        )) {
            $bad += "duplicate candidate id: $($duplicate.Name)"
        }
        $sourceIds = @{}
        foreach ($source in $sources) {
            $sourceIds[[string]$source.id] = $source
            if ($source.provider -notin @('github', 'skill-vault')) {
                $bad += "$($source.id): unsupported provider"
            }
            if ($source.migration_status -notin @('complete', 'needs-review')) {
                $bad += "$($source.id): invalid migration_status"
            }
        }
        $decisionContent = Get-Content -Raw -LiteralPath $decisionPath
        $decisionHeadings = @(
            [regex]::Matches($decisionContent, '(?m)^### (?<heading>.+)$') |
                ForEach-Object { $_.Groups['heading'].Value.Trim() }
        )
        $coveredHeadings = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($source in $sources) {
            foreach ($record in @($source.decision_records)) {
                [void]$coveredHeadings.Add([string]$record)
                if ([string]$record -notin $decisionHeadings) {
                    $bad += "$($source.id): decision record is missing: $record"
                }
            }
        }
        foreach ($candidate in $candidates) {
            if (-not $sourceIds.ContainsKey([string]$candidate.source_id)) {
                $bad += "$($candidate.id): unknown source_id"
                continue
            }
            $source = $sourceIds[[string]$candidate.source_id]
            $repoSlug = (
                ([string]$source.repository).ToLowerInvariant() -replace
                    '[^a-z0-9]+', '-'
            ).Trim('-')
            $pathSlug = (
                ([string]$candidate.source_path).ToLowerInvariant() -replace
                    '[^a-z0-9]+', '-'
            ).Trim('-')
            if ($candidate.id -cne "$repoSlug--$pathSlug") {
                $bad += "$($candidate.id): id does not match repository and path"
            }
            if (
                $candidate.lifecycle_status -notin @(
                    'discovered',
                    'staged',
                    'adopted',
                    'held',
                    'rejected',
                    'update-available'
                )
            ) {
                $bad += "$($candidate.id): invalid lifecycle_status"
            }
            if ($candidate.migration_status -notin @('complete', 'needs-review')) {
                $bad += "$($candidate.id): invalid migration_status"
            }
            [void]$coveredHeadings.Add([string]$candidate.decision_record)
            if ([string]$candidate.decision_record -notin $decisionHeadings) {
                $bad += "$($candidate.id): decision record is missing"
            }
            if ($candidate.lifecycle_status -eq 'adopted') {
                if ([string]::IsNullOrWhiteSpace([string]$candidate.target)) {
                    $bad += "$($candidate.id): adopted candidate has no target"
                } else {
                    $targetSkill = Join-Path $Core (
                        "$($candidate.target)\SKILL.md"
                    )
                    if (-not (Test-Path -LiteralPath $targetSkill -PathType Leaf)) {
                        $bad += "$($candidate.id): adopted target is missing"
                    } elseif (
                        (Split-Path $candidate.target -Leaf) -cne
                        [string]$candidate.canonical_name
                    ) {
                        $bad += "$($candidate.id): canonical name does not match target"
                    }
                }
            }
        }
        foreach ($heading in $decisionHeadings) {
            if (-not $coveredHeadings.Contains($heading)) {
                $bad += "unmigrated decision record: $heading"
            }
        }
    } catch {
        $bad += "registry parse failed: $($_.Exception.Message)"
    }
    if ($bad.Count) {
        return [pscustomobject]@{
            name = 'skill-registry'; passed = $false; message = ($bad -join '; ')
        }
    }
    return [pscustomobject]@{
        name = 'skill-registry'
        passed = $true
        message = "$($sources.Count) source(s), $($candidates.Count) candidate(s) valid"
    }
}

function Get-IndexRoutingCheck {
    param([Parameter(Mandatory)][string]$Core)

    $indexPath = Join-Path $Core 'vault\governance\INDEX.md'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return [pscustomobject]@{
            name = 'index-routing'; passed = $false; message = 'INDEX.md not found'
        }
    }
    $indexDir = Split-Path $indexPath -Parent
    $content = Get-Content -Raw -LiteralPath $indexPath
    $tokens = @(
        [regex]::Matches($content, '`(?<path>\.\./\.\./[^`]+?)`') |
            ForEach-Object { $_.Groups['path'].Value }
    )
    $bad = @()
    $checked = 0
    foreach ($token in $tokens) {
        if ($token.Contains('*')) {
            continue
        }
        $expansions = if (
            $token -match '^(?<prefix>.+)\{(?<opts>[^}]+)\}(?<suffix>.*)$'
        ) {
            $prefix = $Matches['prefix']
            $suffix = $Matches['suffix']
            @($Matches['opts'] -split ',' | ForEach-Object { "$prefix$_$suffix" })
        } else {
            @($token)
        }
        foreach ($expanded in $expansions) {
            if ($expanded.EndsWith('/')) {
                continue
            }
            $checked++
            $resolved = [IO.Path]::GetFullPath((Join-Path $indexDir $expanded))
            if (-not (Test-Path -LiteralPath $resolved)) {
                $bad += "broken routing link: $expanded"
            }
        }
    }
    if ($bad.Count) {
        return [pscustomobject]@{
            name = 'index-routing'; passed = $false; message = ($bad -join '; ')
        }
    }
    return [pscustomobject]@{
        name = 'index-routing'
        passed = $true
        message = "$checked routing link(s) resolved"
    }
}

function Get-SessionInitBudgetCheck {
    param([Parameter(Mandatory)][string]$Core)

    $paths = @(
        'core\constitution\rules.md',
        'vault\README.md',
        'vault\identity\profile.md',
        'vault\memory\memory-summary.md',
        'vault\governance\INDEX.md'
    )
    $missing = @(
        $paths | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $Core $_) -PathType Leaf)
        }
    )
    if ($missing.Count -gt 0) {
        return [pscustomobject]@{
            name = 'session-init-budget'
            passed = $false
            message = "Missing init files: $($missing -join ', ')"
        }
    }
    $bytes = 0
    $lines = 0
    foreach ($path in $paths) {
        $fullPath = Join-Path $Core $path
        $bytes += (Get-Item -LiteralPath $fullPath).Length
        $lines += @([IO.File]::ReadAllLines($fullPath)).Count
    }
    $budget = 10KB
    $message = "$bytes/$budget bytes across $lines lines"
    if ($bytes -le $budget -and $bytes -ge ($budget * 0.8)) {
        $message += ' [WARN: at or above 80% of budget]'
    }
    return [pscustomobject]@{
        name = 'session-init-budget'
        passed = ($bytes -le $budget)
        message = $message
    }
}

function Get-StagingLifecycleCheck {
    param([Parameter(Mandatory)][string]$Core)

    $stagingRoot = Join-Path $Core 'packs\_staging'
    $registryPath = Join-Path $Core 'vault\governance\skill-registry.json'
    try {
        $registry = Get-Content -Raw -LiteralPath $registryPath |
            ConvertFrom-Json
        $candidateById = @{}
        foreach ($candidate in @($registry.candidates)) {
            $candidateById[[string]$candidate.id] = $candidate
        }
        $bad = @()
        foreach ($directory in @(
            Get-ChildItem -LiteralPath $stagingRoot -Directory
        )) {
            if (-not $candidateById.ContainsKey($directory.Name)) {
                $bad += "$($directory.Name): no registry candidate"
                continue
            }
            $status = [string]$candidateById[$directory.Name].lifecycle_status
            if ($status -in @('adopted', 'rejected')) {
                $bad += "$($directory.Name): completed lifecycle $status remains staged"
            }
        }
        return [pscustomobject]@{
            name = 'staging-lifecycle'
            passed = ($bad.Count -eq 0)
            message = if ($bad.Count) {
                $bad -join '; '
            } else { 'Only active or held candidates remain staged' }
        }
    } catch {
        return [pscustomobject]@{
            name = 'staging-lifecycle'
            passed = $false
            message = "Staging lifecycle check failed: $($_.Exception.Message)"
        }
    }
}

function Get-CiGovernanceDedupCheck {
    param([Parameter(Mandatory)][string]$Core)

    $workflowPath = Join-Path $Core '.github\workflows\governance-check.yml'
    $workflow = Get-Content -Raw -LiteralPath $workflowPath
    $duplicated = @(
        @(
            'governance-host-trial.contract.ps1',
            'governance-operation-log.contract.ps1',
            'governance-host-operation-hook.contract.ps1',
            'governance-host-upgrade-gate.contract.ps1',
            'governance-host-run-plan.contract.ps1'
        ) | Where-Object { $workflow.Contains($_) }
    )
    return [pscustomobject]@{
        name = 'ci-governance-dedup'
        passed = ($duplicated.Count -eq 0)
        message = if ($duplicated.Count) {
            'Aggregate GovernanceEvals duplicates: ' + ($duplicated -join ', ')
        } else { 'Heavy governance contracts run only through the aggregate check' }
    }
}

function Get-FleetCatalogCheck {
    param(
        [Parameter(Mandatory)][string]$Core,
        [Parameter(Mandatory)][string]$FleetPath,
        [switch]$SkipFleet
    )

    if ($SkipFleet) {
        return [pscustomobject]@{
            name = 'fleet-catalog'
            passed = $true
            message = 'Skipped for repository-local checks'
        }
    }
    if (-not (Test-Path -LiteralPath $FleetPath -PathType Leaf)) {
        return [pscustomobject]@{
            name = 'fleet-catalog'
            passed = $false
            message = "Fleet file not found: $FleetPath"
        }
    }
    try {
        $items = @(
            Get-Content -Raw -LiteralPath $FleetPath |
                ConvertFrom-Json |
                ForEach-Object { $_ }
        )
        $bad = @()
        foreach ($item in $items) {
            if (-not (Test-Path -LiteralPath $item.path)) {
                $bad += "project path missing: $($item.path)"
            }
            foreach ($pack in @($item.packs)) {
                if ([string]$pack -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
                    $bad += "$($item.path): invalid pack name $pack"
                    continue
                }
                if (
                    -not (
                        Test-Path -LiteralPath (
                            Join-Path $Core "packs\$pack\SKILL.md"
                        ) -PathType Leaf
                    )
                ) {
                    $bad += "$($item.path): missing pack $pack"
                }
            }
        }
        if ($bad.Count) {
            return [pscustomobject]@{
                name = 'fleet-catalog'; passed = $false; message = ($bad -join '; ')
            }
        }
        return [pscustomobject]@{
            name = 'fleet-catalog'
            passed = $true
            message = "$($items.Count) project(s) valid"
        }
    } catch {
        return [pscustomobject]@{
            name = 'fleet-catalog'
            passed = $false
            message = "Invalid JSON: $($_.Exception.Message)"
        }
    }
}

foreach ($checkResult in @(
    Get-SkillCatalogCheck -Core $core
    Get-SkillRegistryCheck -Core $core
    Get-IndexRoutingCheck -Core $core
    Get-SessionInitBudgetCheck -Core $core
    Get-StagingLifecycleCheck -Core $core
    Get-CiGovernanceDedupCheck -Core $core
    Get-FleetCatalogCheck -Core $core -FleetPath $FleetPath -SkipFleet:$SkipFleet
)) {
    Add-Result $checkResult.name $checkResult.passed $checkResult.message
}

function Get-ProjectTextFiles {
    param([Parameter(Mandatory)][string]$Root)

    $allowedRoots = @('core', 'packs', 'scripts', 'vault', 'docs')
    $allowedExtensions = @(
        '.md',
        '.ps1',
        '.psm1',
        '.py',
        '.json',
        '.yaml',
        '.yml',
        '.bat',
        '.cmd'
    )
    $excludedDirectories = @(
        '.git',
        '.local',
        'node_modules',
        '_staging',
        '__pycache__',
        '.venv'
    )
    $excluded = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in $excludedDirectories) {
        [void]$excluded.Add($name)
    }
    $extensions = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($extension in $allowedExtensions) {
        [void]$extensions.Add($extension)
    }
    $pending = [Collections.Generic.Stack[string]]::new()
    foreach ($relativeRoot in $allowedRoots) {
        $path = Join-Path $Root $relativeRoot
        if (Test-Path -LiteralPath $path -PathType Container) {
            $rootItem = Get-Item -LiteralPath $path -Force
            if (-not ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $pending.Push($path)
            }
        }
    }
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in Get-ChildItem -LiteralPath $directory -Force) {
            if ($child.PSIsContainer) {
                if (
                    -not $excluded.Contains($child.Name) -and
                    -not (
                        $child.Attributes -band
                        [IO.FileAttributes]::ReparsePoint
                    )
                ) {
                    $pending.Push($child.FullName)
                }
                continue
            }
            if (
                $child.Name -ne 'projectd-check.ps1' -and
                $extensions.Contains($child.Extension)
            ) {
                $child
            }
        }
    }
}

function Get-StalePackReferenceCheck {
    param([Parameter(Mandatory)][string]$Core)

    $files = @(Get-ProjectTextFiles -Root $Core)
    $hits = @(
        $files |
            Select-String @('frontend-react-angular', 'typescript-node') `
                -SimpleMatch `
                -ErrorAction SilentlyContinue
    )
    if ($hits.Count) {
        return [pscustomobject]@{
            name = 'stale-pack-references'
            passed = $false
            message = (
                (
                    $hits |
                        Select-Object -First 10 |
                        ForEach-Object { "$($_.Path):$($_.LineNumber)" }
                ) -join '; '
            )
        }
    }
    return [pscustomobject]@{
        name = 'stale-pack-references'
        passed = $true
        message = 'No retired pack references found'
    }
}

$staleReferenceResult = Get-StalePackReferenceCheck -Core $core
Add-Result $staleReferenceResult.name $staleReferenceResult.passed $staleReferenceResult.message

function Child([string]$n,[scriptblock]$a){
    try {
        $global:LASTEXITCODE = 0
        $childOutput = @(&$a *>&1)
        $childExitCode = $global:LASTEXITCODE
        if ($childExitCode -ne 0) {
            $details = @(
                $childOutput |
                    Select-Object -Last 12 |
                    ForEach-Object { "$_".Trim() } |
                    Where-Object { $_ }
            ) -join ' | '
            $suffix = if ($details) { " Output: $details" } else { '' }
            throw "Child check exited with code $childExitCode.$suffix"
        }
        Add-Result $n $true 'Child check passed'
    } catch {
        Add-Result $n $false $_.Exception.Message
    }
}

function ChildGroup {
    param(
        [Parameter(Mandatory)][object[]]$Checks,
        [Parameter(Mandatory)][string]$PowerShellPath
    )

    $groupResults = @(
        $Checks | ForEach-Object -Parallel {
            $check = $_
            $childOutput = @(
                & $using:PowerShellPath -NoProfile -File $check.path *>&1
            )
            $childExitCode = $LASTEXITCODE
            $details = @(
                $childOutput |
                    Select-Object -Last 12 |
                    ForEach-Object { "$_".Trim() } |
                    Where-Object { $_ }
            ) -join ' | '
            [pscustomobject]@{
                name = $check.name
                passed = ($childExitCode -eq 0)
                message = if ($childExitCode -eq 0) {
                    'Child check passed'
                } elseif ($details) {
                    "Child check exited with code $childExitCode. Output: $details"
                } else {
                    "Child check exited with code $childExitCode."
                }
            }
        } -ThrottleLimit ([Math]::Min(5, $Checks.Count))
    )
    foreach ($groupResult in $groupResults) {
        Add-Result `
            $groupResult.name `
            ([bool]$groupResult.passed) `
            ([string]$groupResult.message)
    }
}
$pwsh=Get-Command pwsh -ErrorAction SilentlyContinue
if($null -eq $pwsh){
    Add-Result 'fleet-inspect-contract' $false 'pwsh executable not found'
    Add-Result 'skill-scout-contract' $false 'pwsh executable not found'
    Add-Result 'skill-update-check-contract' $false 'pwsh executable not found'
    Add-Result 'claude-switch-account-contract' $false 'pwsh executable not found'
    Add-Result 'usage-contract' $false 'pwsh executable not found'
    Add-Result 'codex-usage-ledger-contract' $false 'pwsh executable not found'
    Add-Result 'claude-usage-ledger-contract' $false 'pwsh executable not found'
    Add-Result 'usage-export-gate-contract' $false 'pwsh executable not found'
    Add-Result 'usage-merge-contract' $false 'pwsh executable not found'
    Add-Result 'usage-report-contract' $false 'pwsh executable not found'
}else{
    Child 'fleet-inspect-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\fleet-inspect.contract.ps1'
        )
    }
    Child 'skill-scout-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'core\skills\skill-scout\tests\skill-scout.contract.ps1'
        )
    }
    Child 'skill-update-check-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core (
                'core\skills\skill-update-check\tests\' +
                'skill-update-check.contract.ps1'
            )
        )
    }
    Child 'claude-switch-account-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\claude-switch-account.contract.ps1'
        )
    }
    Child 'usage-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\usage-contract.contract.ps1'
        )
    }
    Child 'codex-usage-ledger-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\codex-usage-ledger.contract.ps1'
        )
    }
    Child 'claude-usage-ledger-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\claude-usage-ledger.contract.ps1'
        )
    }
    Child 'usage-export-gate-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\usage-export-gate.contract.ps1'
        )
    }
    Child 'usage-merge-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\usage-merge.contract.ps1'
        )
    }
    Child 'usage-report-contract' {
        & $pwsh.Source -NoProfile -File (
            Join-Path $core 'scripts\tests\usage-report.contract.ps1'
        )
    }
}
if (-not $SkipWiring) {
    if ($null -eq $pwsh) {
        if (-not $SkipGlobal) {
            Add-Result 'global-wiring' $false (
                'pwsh executable not found; install PowerShell 7 to run wiring checks'
            )
        }
        Add-Result 'fleet-wiring' $false (
            'pwsh executable not found; install PowerShell 7 to run wiring checks'
        )
    } else {
        if (-not $SkipGlobal) {
            Child 'global-wiring' {
                & (Join-Path $PSScriptRoot 'setup.ps1') -Mode Check
            }
        }
        Child 'fleet-wiring' {
            & (Join-Path $PSScriptRoot 'fleet-governance.ps1') `
                -Mode Check `
                -FleetPath $FleetPath
        }
    }
} else {
    Add-Result 'wiring' $true 'Skipped for isolated fixture checks'
}

if ($GovernanceEvals) {
    if ($null -eq $pwsh) {
        Add-Result 'governance-structural-evals' $false 'pwsh executable not found'
        Add-Result 'governance-behavior-catalog' $false 'pwsh executable not found'
        Add-Result 'governance-asset-inventory' $false 'pwsh executable not found'
        Add-Result 'governance-security-traces' $false 'pwsh executable not found'
        Add-Result 'governance-host-trial-contract' $false 'pwsh executable not found'
        Add-Result 'governance-operation-log-contract' $false 'pwsh executable not found'
        Add-Result 'governance-host-operation-hook-contract' $false 'pwsh executable not found'
        Add-Result 'governance-host-upgrade-gate-contract' $false 'pwsh executable not found'
        Add-Result 'governance-host-run-plan-contract' $false 'pwsh executable not found'
    } else {
        Child 'governance-structural-evals' {
            & $pwsh.Source -NoProfile -File (
                Join-Path $core 'scripts\governance-eval.ps1'
            )
        }
        Child 'governance-behavior-catalog' {
            & $pwsh.Source -NoProfile -File (
                Join-Path $core 'scripts\governance-behavior-eval.ps1'
            ) -CatalogOnly
        }
        Child 'governance-asset-inventory' {
            & $pwsh.Source -NoProfile -File (
                Join-Path $core 'scripts\governance-asset-inventory.ps1'
            )
        }
        Child 'governance-security-traces' {
            & $pwsh.Source -NoProfile -File (
                Join-Path $core 'scripts\governance-trace-eval.ps1'
            )
        }
        ChildGroup -PowerShellPath $pwsh.Source -Checks @(
            [pscustomobject]@{
                name = 'governance-host-trial-contract'
                path = Join-Path $core (
                    'scripts\tests\governance-host-trial.contract.ps1'
                )
            }
            [pscustomobject]@{
                name = 'governance-operation-log-contract'
                path = Join-Path $core (
                    'scripts\tests\governance-operation-log.contract.ps1'
                )
            }
            [pscustomobject]@{
                name = 'governance-host-operation-hook-contract'
                path = Join-Path $core (
                    'scripts\tests\governance-host-operation-hook.contract.ps1'
                )
            }
            [pscustomobject]@{
                name = 'governance-host-upgrade-gate-contract'
                path = Join-Path $core (
                    'scripts\tests\governance-host-upgrade-gate.contract.ps1'
                )
            }
            [pscustomobject]@{
                name = 'governance-host-run-plan-contract'
                path = Join-Path $core (
                    'scripts\tests\governance-host-run-plan.contract.ps1'
                )
            }
        )
    }
}

$failed = @($results | Where-Object { -not $_.passed })
if ($Json) {
    [pscustomobject]@{
        passed = -not $failed.Count
        checks = $results
    } | ConvertTo-Json -Depth 4
} else {
    $results | ForEach-Object {
        $state = if ($_.passed) { 'PASS' } else { 'FAIL' }
        "[$state] $($_.name): $($_.message)"
    }
    "Summary: $(@($results | Where-Object passed).Count) passed, " +
        "$($failed.Count) failed."
}
if ($failed.Count) {
    exit 1
}
