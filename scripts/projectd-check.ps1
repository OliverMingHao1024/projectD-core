[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$FleetPath,[switch]$Json,[switch]$SkipGlobal,[switch]$SkipWiring)
$ErrorActionPreference='Stop';$core=[IO.Path]::GetFullPath($ProjectRoot);if([string]::IsNullOrWhiteSpace($FleetPath)){$FleetPath=Join-Path $core 'fleet\fleet.json'};$results=@()
function Add-Result([string]$n,[bool]$p,[string]$m){$script:results+=,[pscustomobject]@{name=$n;passed=$p;message=$m}}
$skillRoots = @(
    Join-Path $core 'core\skills'
    Join-Path $core 'packs'
)
$skills = @(
    foreach ($root in $skillRoots) {
        Get-ChildItem -LiteralPath $root -Directory |
            Where-Object Name -NotLike '_*'
    }
)
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
    }
}
if ($bad.Count) {
    Add-Result 'skill-catalog' $false ($bad -join '; ')
} else {
    Add-Result 'skill-catalog' $true "$($skills.Count) canonical skill(s) valid"
}
$registryPath = Join-Path $core 'vault\governance\skill-registry.json'
$decisionPath = Join-Path $core 'vault\governance\skill-candidates.md'
$bad = @()
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
        if ($source.provider -ne 'github') {
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
                $targetSkill = Join-Path $core (
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
    Add-Result 'skill-registry' $false ($bad -join '; ')
} else {
    Add-Result 'skill-registry' $true (
        "$($sources.Count) source(s), $($candidates.Count) candidate(s) valid"
    )
}
if(-not(Test-Path $FleetPath)){Add-Result 'fleet-catalog' $false "Fleet file not found: $FleetPath"}else{try{$items=@(Get-Content -Raw $FleetPath|ConvertFrom-Json|ForEach-Object{$_});$bad=@();foreach($item in $items){if(-not(Test-Path $item.path)){$bad+="project path missing: $($item.path)"};foreach($pack in @($item.packs)){if(-not(Test-Path (Join-Path $core "packs\$pack\SKILL.md"))){$bad+="$($item.path): missing pack $pack"}}};if($bad.Count){Add-Result 'fleet-catalog' $false ($bad -join '; ')}else{Add-Result 'fleet-catalog' $true "$($items.Count) project(s) valid"}}catch{Add-Result 'fleet-catalog' $false "Invalid JSON: $($_.Exception.Message)"}}
$files=@(Get-ChildItem $core -Recurse -File|Where-Object{$_.FullName -notmatch '\\.git\\|\\.local\\|\\node_modules\\|\\packs\\_staging\\' -and $_.Name -ne 'projectd-check.ps1'});$hits=@($files|Select-String @('frontend-react-angular','typescript-node') -SimpleMatch -ErrorAction SilentlyContinue);if($hits.Count){Add-Result 'stale-pack-references' $false (($hits|Select-Object -First 10|%{"$($_.Path):$($_.LineNumber)"}) -join '; ')}else{Add-Result 'stale-pack-references' $true 'No retired pack references found'}
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
$pwsh=Get-Command pwsh -ErrorAction SilentlyContinue
if($null -eq $pwsh){
    Add-Result 'skill-scout-contract' $false 'pwsh executable not found'
    Add-Result 'skill-update-check-contract' $false 'pwsh executable not found'
}else{
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
}
if(-not$SkipWiring){if($null -eq $pwsh){if(-not$SkipGlobal){Add-Result 'global-wiring' $false 'pwsh executable not found; install PowerShell 7 to run wiring checks'};Add-Result 'fleet-wiring' $false 'pwsh executable not found; install PowerShell 7 to run wiring checks'}else{if(-not$SkipGlobal){Child 'global-wiring'{& (Join-Path $PSScriptRoot 'setup.ps1') -Mode Check}};Child 'fleet-wiring'{& (Join-Path $PSScriptRoot 'fleet-governance.ps1') -Mode Check -FleetPath $FleetPath}}}else{Add-Result 'wiring' $true 'Skipped for isolated fixture checks'}
$failed=@($results|?{-not$_.passed});if($Json){[pscustomobject]@{passed=(!$failed.Count);checks=$results}|ConvertTo-Json -Depth 4}else{$results|%{"[$(if($_.passed){'PASS'}else{'FAIL'})] $($_.name): $($_.message)"};"Summary: $(@($results|? passed).Count) passed, $($failed.Count) failed."};if($failed.Count){exit 1}
