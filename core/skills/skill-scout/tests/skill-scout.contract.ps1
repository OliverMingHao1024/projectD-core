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

Write-Output 'SKILL_SCOUT_CONTRACT_OK'
