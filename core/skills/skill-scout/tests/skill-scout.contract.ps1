[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$SkillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Script = Join-Path $SkillRoot 'scripts\skill-scout.ps1'
$Fixture = Join-Path $PSScriptRoot 'fixtures\candidates.json'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$sourceResult = & $Script `
    -Source 'https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs' `
    -FixturePath $Fixture |
    ConvertFrom-Json

Assert-True ($sourceResult.mode -eq 'source') 'Exact URL must select source mode.'
Assert-True (-not $sourceResult.expanded_scope) 'Search must not expand scope.'
Assert-True (-not $sourceResult.staged) 'Inspection must not stage content.'
Assert-True (
    @($sourceResult.candidates).Count -eq 1
) 'Exact eligible source must return one candidate.'
Assert-True (
    $sourceResult.candidates[0].id -eq
    'mattpocock-skills--skills-engineering-grill-with-docs'
) 'Candidate id must include the complete source path.'

$truncatedResult = & $Script `
    -Source 'https://github.com/example/skills/tree/main/skills/truncated-tree' `
    -FixturePath $Fixture |
    ConvertFrom-Json

Assert-True (
    @($truncatedResult.candidates).Count -eq 0
) 'A truncated Git tree must not produce a verifiable candidate.'
Assert-True (
    @($truncatedResult.rejections |
        Where-Object {
            $_.source -eq 'example/skills/skills/truncated-tree' -and
            $_.reasons -match 'truncated'
        }).Count -eq 1
) 'A truncated Git tree must be rejected with an explicit reason.'

$capabilityResult = & $Script `
    -Capability 'merge conflict' `
    -Query 'merge conflict' `
    -MaxCandidates 3 `
    -FixturePath $Fixture |
    ConvertFrom-Json

Assert-True (
    @($capabilityResult.queries).Count -le 3
) 'Capability mode must use at most three queries.'
Assert-True (
    @($capabilityResult.candidates).Count -eq 3
) 'Capability mode must stop at three eligible candidates.'
Assert-True (
    @($capabilityResult.rejections |
        Where-Object source -Like 'unsafe/skills/*').Count -eq 1
) 'Unclear licenses must be rejected.'
Assert-True (
    -not (Test-Path -LiteralPath (
        Join-Path $SkillRoot '..\..\..\packs\_staging\unsafe-skills'
    ))
) 'Contract run must not write staging.'

$VerdictSchema = Join-Path $SkillRoot 'references\review-verdict.schema.json'
$passVerdictJson = Get-Content -Raw -LiteralPath (
    Join-Path $PSScriptRoot 'fixtures\review-verdict-pass.json'
)

function Test-Verdict {
    param([Parameter(Mandatory)][string]$Json)
    return [bool](Test-Json -Json $Json -SchemaFile $VerdictSchema `
        -ErrorAction SilentlyContinue)
}

function Set-VerdictField {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][hashtable]$Fields
    )
    $verdict = $Json | ConvertFrom-Json
    foreach ($key in $Fields.Keys) {
        $verdict | Add-Member -NotePropertyName $key `
            -NotePropertyValue $Fields[$key] -Force
    }
    return ($verdict | ConvertTo-Json -Depth 10)
}

Assert-True (Test-Verdict $passVerdictJson) (
    'A clean passing verdict must validate.'
)
foreach ($redFlag in @(
    @{ has_broad_scope_hooks = $true },
    @{ has_undisclosed_telemetry = $true },
    @{ has_cross_service_secret_routing = $true },
    @{ has_coercive_text = $true },
    @{ description_matches_behavior = $false }
)) {
    $flagName = @($redFlag.Keys)[0]
    Assert-True (-not (Test-Verdict (Set-VerdictField $passVerdictJson $redFlag))) (
        "A verdict with $flagName set must not be allowed to pass."
    )
    Assert-True (Test-Verdict (Set-VerdictField $passVerdictJson ($redFlag + @{
        passes = $false
        violations = @('hooks/hooks.json: example violation')
    }))) "A failing verdict with $flagName and a violation must validate."
}
Assert-True (-not (Test-Verdict (Set-VerdictField $passVerdictJson @{
    passes = $false
}))) 'A failing verdict must cite at least one violation.'
Assert-True (-not (Test-Verdict (Set-VerdictField $passVerdictJson @{
    unexpected_field = $true
}))) 'A verdict must reject unknown fields.'

Write-Output 'SKILL_SCOUT_CONTRACT_OK'
