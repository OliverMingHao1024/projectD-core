[CmdletBinding(DefaultParameterSetName = 'Source')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Source')]
    [string]$Source,

    [Parameter(Mandatory, ParameterSetName = 'Capability')]
    [string]$Capability,

    [Parameter(ParameterSetName = 'Capability')]
    [ValidateCount(0, 3)]
    [string[]]$Query = @(),

    [Parameter(ParameterSetName = 'Capability')]
    [ValidateRange(1, 3)]
    [int]$MaxCandidates = 3,

    [string]$FixturePath
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Slug {
    param([Parameter(Mandatory)][string]$Value)

    return (
        $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    ).Trim('-')
}

function Get-CandidateId {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$SourcePath
    )

    return (
        "$(ConvertTo-Slug $Repository)--$(ConvertTo-Slug $SourcePath)"
    )
}

function Get-SourceIdentity {
    param([Parameter(Mandatory)][string]$Value)

    $trimmed = $Value.Trim().TrimEnd('/')
    if (
        $trimmed -match
        '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/tree/(?<ref>[^/]+)/(?<path>.+)$'
    ) {
        return [pscustomobject]@{
            Repository = "$($Matches.owner)/$($Matches.repo)"
            Ref = $Matches.ref
            SourcePath = $Matches.path.Trim('/')
        }
    }
    if (
        $trimmed -match
        '^(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)/(?<path>.+)$'
    ) {
        return [pscustomobject]@{
            Repository = "$($Matches.owner)/$($Matches.repo)"
            Ref = $null
            SourcePath = $Matches.path.Trim('/')
        }
    }
    throw (
        'Source must be a GitHub Skill URL or owner/repo/path. ' +
        'Repository-only input is intentionally unsupported.'
    )
}

function Get-ContentDigest {
    param([Parameter(Mandatory)][object[]]$Files)

    $manifest = (
        $Files |
            Sort-Object path |
            ForEach-Object { "$($_.path):$($_.sha)" }
    ) -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($manifest)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return 'sha256:' + [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-SkillMetadata {
    param([Parameter(Mandatory)][string]$Content)

    $frontmatter = [regex]::Match(
        $Content,
        '\A---\r?\n(?<yaml>.*?)\r?\n---(?:\r?\n|\z)',
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $frontmatter.Success) {
        return [pscustomobject]@{
            Valid = $false
            Name = $null
            Description = $null
            ExtraKeys = @()
            Reason = 'SKILL.md has no valid frontmatter boundary.'
        }
    }
    $lines = @(
        $frontmatter.Groups['yaml'].Value -split '\r?\n' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $name = @($lines | Where-Object { $_ -match '^name:\s*(.+?)\s*$' })
    $description = @(
        $lines | Where-Object { $_ -match '^description:\s*(.+?)\s*$' }
    )
    if ($name.Count -ne 1 -or $description.Count -ne 1) {
        return [pscustomobject]@{
            Valid = $false
            Name = $null
            Description = $null
            ExtraKeys = @()
            Reason = 'SKILL.md must have one non-empty name and description.'
        }
    }
    $keys = @(
        $lines | ForEach-Object {
            if ($_ -match '^([A-Za-z0-9_-]+):') { $Matches[1] }
        }
    )
    return [pscustomobject]@{
        Valid = $true
        Name = ($name[0] -replace '^name:\s*', '').Trim('"', "'")
        Description = (
            $description[0] -replace '^description:\s*', ''
        ).Trim('"', "'")
        ExtraKeys = @($keys | Where-Object { $_ -notin @('name', 'description') })
        Reason = $null
    }
}

function Test-ClearLicense {
    param([AllowNull()][string]$Spdx)

    return (
        -not [string]::IsNullOrWhiteSpace($Spdx) -and
        $Spdx.ToUpperInvariant() -notin @(
            'NOASSERTION',
            'OTHER',
            'NONE'
        ) -and
        $Spdx -notlike 'LicenseRef-*'
    )
}

function Get-DependencyHints {
    param([Parameter(Mandatory)][string]$Content)

    $namedSkills = [regex]::Matches(
        $Content,
        '`/?(?<name>[a-z0-9][a-z0-9-]+)`\s+(?:Skill|skill)'
    )
    $slashSkills = [regex]::Matches(
        $Content,
        '`/(?<name>[a-z0-9][a-z0-9-]+)`'
    )
    return @(
        @($namedSkills) + @($slashSkills) |
            ForEach-Object { $_.Groups['name'].Value } |
            Sort-Object -Unique
    )
}

function ConvertTo-IsoTimestamp {
    param([AllowNull()][object]$Value)

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    return [datetime]::Parse([string]$Value).ToUniversalTime().ToString(
        'yyyy-MM-ddTHH:mm:ssZ'
    )
}

function Get-ExecutableFiles {
    param([Parameter(Mandatory)][object[]]$Files)

    return @(
        $Files |
            Where-Object {
                $_.path -match (
                    '(^|/)(hooks?|scripts?)/|' +
                    '\.(?:ps1|sh|bash|py|js|mjs|cjs|ts|cmd|bat|exe)$'
                )
            } |
            Select-Object -ExpandProperty path
    )
}

function ConvertTo-InspectedCandidate {
    param(
        [Parameter(Mandatory)][object]$Item,
        [switch]$RequireDirectFit
    )

    $reasons = [Collections.Generic.List[string]]::new()
    if (-not (Test-ClearLicense ([string]$Item.license_spdx))) {
        $reasons.Add('License is missing, unclear, or non-SPDX.')
    }
    $metadata = Get-SkillMetadata ([string]$Item.skill_content)
    if (-not $metadata.Valid) {
        $reasons.Add($metadata.Reason)
    }
    $skillFile = @($Item.files | Where-Object path -EQ 'SKILL.md')
    if ($skillFile.Count -ne 1) {
        $reasons.Add('Source path must contain exactly one root SKILL.md.')
    }
    if ($RequireDirectFit -and [int]$Item.relevance -lt 500) {
        $reasons.Add('Search hit mentions the capability but is not a direct fit.')
    }
    $risks = [Collections.Generic.List[string]]::new()
    if ($metadata.ExtraKeys.Count -gt 0) {
        $risks.Add(
            "Non-portable frontmatter: $($metadata.ExtraKeys -join ', ')."
        )
    }
    $executables = @(Get-ExecutableFiles @($Item.files))
    if ($executables.Count -gt 0) {
        $risks.Add('Candidate includes executable or hook files; do not run them.')
    }
    $sourceUrl = (
        "https://github.com/$($Item.repository)/tree/" +
        "$($Item.commit)/$($Item.source_path)"
    )
    return [pscustomobject]@{
        Eligible = $reasons.Count -eq 0
        Reasons = $reasons.ToArray()
        Candidate = [pscustomobject]@{
            id = Get-CandidateId `
                -Repository ([string]$Item.repository) `
                -SourcePath ([string]$Item.source_path)
            repository = [string]$Item.repository
            source_path = [string]$Item.source_path
            source_url = $sourceUrl
            commit = [string]$Item.commit
            license_spdx = [string]$Item.license_spdx
            name = $metadata.Name
            description = $metadata.Description
            content_digest = Get-ContentDigest @($Item.files)
            dependency_hints = @(Get-DependencyHints ([string]$Item.skill_content))
            executable_files = $executables
            relevance = [int]$Item.relevance
            stars = [int]$Item.stars
            updated_at = ConvertTo-IsoTimestamp $Item.updated_at
            cross_agent_risks = $risks.ToArray()
        }
    }
}

function Invoke-GhJson {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & gh $Command @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "gh $Command failed with exit code $LASTEXITCODE."
    }
    return ($output | Out-String | ConvertFrom-Json)
}

function Get-LiveSourceItem {
    param([Parameter(Mandatory)][object]$Identity)

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) is required for live inspection.'
    }
    $repo = Invoke-GhJson api @("repos/$($Identity.Repository)")
    $ref = if ($Identity.Ref) {
        $Identity.Ref
    } else {
        [string]$repo.default_branch
    }
    $commit = Invoke-GhJson api @(
        "repos/$($Identity.Repository)/commits/$ref"
    )
    $commitSha = [string]$commit.sha
    $license = Invoke-GhJson api @(
        "repos/$($Identity.Repository)/license?ref=$commitSha"
    )
    $tree = Invoke-GhJson api @(
        "repos/$($Identity.Repository)/git/trees/$commitSha`?recursive=1"
    )
    $prefix = $Identity.SourcePath.TrimEnd('/') + '/'
    $files = @(
        $tree.tree |
            Where-Object {
                $_.type -eq 'blob' -and (
                    $_.path -eq "$($Identity.SourcePath)/SKILL.md" -or
                    $_.path.StartsWith($prefix)
                )
            } |
            ForEach-Object {
                [pscustomobject]@{
                    path = $_.path.Substring($prefix.Length)
                    sha = [string]$_.sha
                }
            }
    )
    $skillContentResponse = Invoke-GhJson api @(
        "repos/$($Identity.Repository)/contents/" +
        "$($Identity.SourcePath)/SKILL.md`?ref=$commitSha"
    )
    $encoded = ([string]$skillContentResponse.content) -replace '\s', ''
    $skillContent = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($encoded)
    )
    return [pscustomobject]@{
        repository = $Identity.Repository
        source_path = $Identity.SourcePath
        ref = $ref
        commit = $commitSha
        license_spdx = [string]$license.license.spdx_id
        stars = [int]$repo.stargazers_count
        updated_at = [string]$repo.pushed_at
        relevance = 100
        matches = @()
        files = $files
        skill_content = $skillContent
    }
}

function Get-LiveCapabilityItems {
    param(
        [Parameter(Mandatory)][string[]]$Queries,
        [Parameter(Mandatory)][int]$Limit
    )

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) is required for live search.'
    }
    $hits = [Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($searchQuery in $Queries) {
        $results = Invoke-GhJson search @(
            'code',
            "$searchQuery filename:SKILL.md",
            '--json',
            'repository,path,url',
            '--limit',
            '10'
        )
        foreach ($result in @($results)) {
            $repository = [string]$result.repository.nameWithOwner
            $sourcePath = Split-Path ([string]$result.path) -Parent
            $key = "$repository/$sourcePath".ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                continue
            }
            $seen[$key] = $true
            $normalizedPath = ($sourcePath -replace '\\', '/')
            $pathLeaf = Split-Path $normalizedPath -Leaf
            $querySlug = ConvertTo-Slug $searchQuery
            $preliminaryScore = if (
                (ConvertTo-Slug $pathLeaf) -eq $querySlug
            ) {
                1000
            } elseif (
                (ConvertTo-Slug $normalizedPath).Contains($querySlug)
            ) {
                500
            } else {
                0
            }
            $hits.Add([pscustomobject]@{
                Repository = $repository
                SourcePath = $normalizedPath
                Query = $searchQuery
                PreliminaryScore = $preliminaryScore
            })
        }
    }
    $items = [Collections.Generic.List[object]]::new()
    $inspectLimit = [Math]::Min(10, [Math]::Max(3, $Limit * 3))
    foreach ($hit in @(
        $hits |
            Sort-Object PreliminaryScore -Descending |
            Select-Object -First $inspectLimit
    )) {
        try {
            $identity = [pscustomobject]@{
                Repository = $hit.Repository
                Ref = $null
                SourcePath = $hit.SourcePath
            }
            $item = Get-LiveSourceItem $identity
            $metadata = Get-SkillMetadata ([string]$item.skill_content)
            $queryText = ([string]$hit.Query).ToLowerInvariant()
            $querySlug = ConvertTo-Slug ([string]$hit.Query)
            $score = [int]$hit.PreliminaryScore
            if ((ConvertTo-Slug ([string]$metadata.Name)) -eq $querySlug) {
                $score += 2000
            }
            if (
                ([string]$metadata.Description).ToLowerInvariant().Contains(
                    $queryText
                )
            ) {
                $score += 1000
            }
            if (
                ([string]$item.skill_content).ToLowerInvariant().Contains(
                    $queryText
                )
            ) {
                $score += 100
            }
            $item.relevance = $score
            $items.Add($item)
        } catch {
            # An inaccessible or malformed hit is not a candidate.
        }
    }
    return @($items.ToArray() | Sort-Object relevance -Descending)
}

$mode = if ($PSCmdlet.ParameterSetName -eq 'Source') {
    'source'
} else {
    'capability'
}
[object[]]$queries = @()
if ($mode -eq 'capability') {
    $queries = if ($Query.Count -gt 0) { @($Query) } else { @($Capability) }
}
if ($queries.Count -gt 3) {
    throw 'Capability search accepts at most three precise queries.'
}

$fixtureItems = if ($FixturePath) {
    @((Get-Content -Raw -LiteralPath $FixturePath | ConvertFrom-Json).items)
} else {
    @()
}

if ($mode -eq 'source') {
    $identity = Get-SourceIdentity $Source
    $items = if ($FixturePath) {
        @(
            $fixtureItems |
                Where-Object {
                    $_.repository -eq $identity.Repository -and
                    $_.source_path -eq $identity.SourcePath
                }
        )
    } else {
        @(Get-LiveSourceItem $identity)
    }
} else {
    if ($FixturePath) {
        $needles = @($Capability) + @($queries)
        $items = @(
            $fixtureItems |
                Where-Object {
                    $matches = @($_.matches)
                    @(
                        foreach ($needle in $needles) {
                            $matches | Where-Object {
                                $_.ToLowerInvariant().Contains(
                                    $needle.ToLowerInvariant()
                                ) -or
                                $needle.ToLowerInvariant().Contains(
                                    $_.ToLowerInvariant()
                                )
                            }
                        }
                    ).Count -gt 0
                } |
                Sort-Object `
                    @{ Expression = 'relevance'; Descending = $true },
                    @{ Expression = 'stars'; Descending = $true }
        )
    } else {
        $items = @(Get-LiveCapabilityItems $queries $MaxCandidates)
    }
}

$candidates = [Collections.Generic.List[object]]::new()
$rejections = [Collections.Generic.List[object]]::new()
foreach ($item in $items) {
    $inspection = ConvertTo-InspectedCandidate `
        -Item $item `
        -RequireDirectFit:($mode -eq 'capability')
    if ($inspection.Eligible) {
        if ($candidates.Count -lt $MaxCandidates) {
            $candidates.Add($inspection.Candidate)
        }
    } else {
        $rejections.Add([pscustomobject]@{
            source = "$($item.repository)/$($item.source_path)"
            reasons = $inspection.Reasons
        })
    }
}

[pscustomobject]@{
    schema_version = 1
    mode = $mode
    request = if ($mode -eq 'source') { $Source } else { $Capability }
    queries = @($queries)
    expanded_scope = $false
    staged = $false
    candidates = $candidates.ToArray()
    rejections = $rejections.ToArray()
} | ConvertTo-Json -Depth 10
