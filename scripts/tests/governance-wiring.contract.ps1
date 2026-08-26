[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TempRoot
)

$ErrorActionPreference = 'Stop'
$Module = Join-Path $PSScriptRoot '..\ProjectD.GovernanceWiring.psm1'
Import-Module (Resolve-Path $Module) -Force

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$Root = [IO.Path]::GetFullPath($TempRoot)
New-Item -ItemType Directory -Path $Root -Force | Out-Null
$StatePath = Join-Path $Root 'state.json'
$Start = '<!-- PROJECTD_CORE_START -->'
$End = '<!-- PROJECTD_CORE_END -->'
$Block = "$Start`n## Managed`nexpected`n$End"

# Full managed-block lifecycle.
$Entry = Join-Path $Root 'entry.md'
Set-Content -LiteralPath $Entry -Value "prefix`n" -Encoding utf8 -NoNewline
$BlockResource = New-ManagedBlockResource `
    -Path $Entry -BlockStart $Start -BlockEnd $End -Content $Block -Owner 'test'
Invoke-GovernanceWiring `
    -Resources @($BlockResource) -Action Apply -StatePath $StatePath | Out-Null
$Applied = Get-Content -Raw -LiteralPath $Entry
Assert-True ($Applied.Contains('prefix')) 'Apply must preserve existing content.'
Assert-True ($Applied.Contains('expected')) 'Apply must add the expected block.'
$Check = @(Invoke-GovernanceWiring `
    -Resources @($BlockResource) -Action Check -StatePath $StatePath)
Assert-True ($Check[0].State -eq 'Compliant') 'Check must report Compliant.'
Invoke-GovernanceWiring `
    -Resources @($BlockResource) -Action Remove -StatePath $StatePath | Out-Null
$Removed = Get-Content -Raw -LiteralPath $Entry
Assert-True ($Removed.Contains('prefix')) 'Remove must preserve non-owned content.'
Assert-True (-not $Removed.Contains($Start)) 'Remove must delete the owned block.'

# Partial markers are a preflight conflict and must remain untouched.
$Conflict = Join-Path $Root 'conflict.md'
$Partial = "keep`n$Start`nbroken"
Set-Content -LiteralPath $Conflict -Value $Partial -Encoding utf8 -NoNewline
$ConflictResource = New-ManagedBlockResource `
    -Path $Conflict -BlockStart $Start -BlockEnd $End -Content $Block -Owner 'test'
$ConflictFailed = $false
try {
    Invoke-GovernanceWiring `
        -Resources @($ConflictResource) -Action Apply -StatePath $StatePath | Out-Null
} catch {
    $ConflictFailed = $true
}
Assert-True $ConflictFailed 'Partial markers must fail preflight.'
Assert-True (
    (Get-Content -Raw -LiteralPath $Conflict) -eq $Partial
) 'Conflict preflight must not mutate the file.'

# Injected failure rolls back every mutation from this run.
$First = Join-Path $Root 'first.md'
$Second = Join-Path $Root 'second.md'
$FirstResource = New-ManagedBlockResource `
    -Path $First -BlockStart $Start -BlockEnd $End -Content $Block -Owner 'test'
$SecondResource = New-ManagedBlockResource `
    -Path $Second -BlockStart $Start -BlockEnd $End -Content $Block -Owner 'test'
$RollbackFailed = $false
try {
    Invoke-GovernanceWiring `
        -Resources @($FirstResource, $SecondResource) `
        -Action Apply `
        -StatePath $StatePath `
        -AfterMutation {
            param($Item)
            throw "injected failure after $($Item.Resource.Path)"
        } | Out-Null
} catch {
    $RollbackFailed = $true
}
Assert-True $RollbackFailed 'Injected mutation failure must escape.'
Assert-True (-not (Test-Path -LiteralPath $First)) 'First mutation must roll back.'
Assert-True (-not (Test-Path -LiteralPath $Second)) 'Second file must stay absent.'

# File copies are removed only while ownership is still proven.
$Source = Join-Path $Root 'source.md'
$Target = Join-Path $Root 'target.md'
Set-Content -LiteralPath $Source -Value 'canonical' -Encoding utf8 -NoNewline
$CopyResource = New-FileCopyResource `
    -Path $Target -Source $Source -Owner 'test'
Invoke-GovernanceWiring `
    -Resources @($CopyResource) -Action Apply -StatePath $StatePath | Out-Null
Set-Content -LiteralPath $Target -Value 'user modified' -Encoding utf8 -NoNewline
$OwnershipFailed = $false
try {
    Invoke-GovernanceWiring `
        -Resources @($CopyResource) -Action Remove -StatePath $StatePath | Out-Null
} catch {
    $OwnershipFailed = $true
}
Assert-True $OwnershipFailed 'Modified copied file must become a conflict.'
Assert-True (
    (Get-Content -Raw -LiteralPath $Target) -eq 'user modified'
) 'Non-owned file content must remain untouched.'

# Environment changes use an adapter-friendly Process scope in tests.
$EnvironmentName = "PROJECTD_WIRING_TEST_$PID"
$EnvironmentResource = New-EnvironmentResource `
    -Name $EnvironmentName -Value 'expected' -Scope 'Process' -Owner 'test'
Invoke-GovernanceWiring `
    -Resources @($EnvironmentResource) -Action Apply -StatePath $StatePath | Out-Null
Assert-True (
    [Environment]::GetEnvironmentVariable($EnvironmentName, 'Process') -eq 'expected'
) 'Apply must set the expected environment value.'
Invoke-GovernanceWiring `
    -Resources @($EnvironmentResource) -Action Remove -StatePath $StatePath | Out-Null
Assert-True (
    [string]::IsNullOrEmpty(
        [Environment]::GetEnvironmentVariable($EnvironmentName, 'Process')
    )
) 'Remove must clear an owned environment value.'

# Global desired state owns every adapter through one lifecycle.
$Core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$GlobalRoot = Join-Path $Root 'global'
$GlobalState = New-GlobalGovernanceWiring `
    -Core $Core `
    -ClaudeHome (Join-Path $GlobalRoot 'claude') `
    -CodexHome (Join-Path $GlobalRoot 'codex') `
    -SharedAgentSkills (Join-Path $GlobalRoot 'agents\skills') `
    -EnvironmentScope Process `
    -StatePath (Join-Path $GlobalRoot 'state.json')
$UnownedGlobalRoot = Join-Path $Root 'unowned-global'
$UnownedGlobal = New-GlobalGovernanceWiring `
    -Core $Core `
    -ClaudeHome (Join-Path $UnownedGlobalRoot 'claude') `
    -CodexHome (Join-Path $UnownedGlobalRoot 'codex') `
    -SharedAgentSkills (Join-Path $UnownedGlobalRoot 'agents\skills') `
    -EnvironmentScope Process `
    -StatePath (Join-Path $UnownedGlobalRoot 'state.json')
$UnownedPackPath = Join-Path $UnownedGlobalRoot 'agents\skills\python'
New-Item -ItemType Directory -Path (Split-Path $UnownedPackPath -Parent) `
    -Force | Out-Null
New-Item -ItemType Junction -Path $UnownedPackPath `
    -Target (Join-Path $Core 'packs\python') | Out-Null
$UnownedRemovalFailed = $false
try {
    Invoke-GovernanceWiring `
        -Resources $UnownedGlobal.Resources `
        -Action Apply `
        -StatePath $UnownedGlobal.StatePath | Out-Null
} catch {
    $UnownedRemovalFailed = $true
}
Assert-True $UnownedRemovalFailed (
    'Absent desired state must not remove a matching unowned junction.'
)
Assert-True (Test-Path -LiteralPath $UnownedPackPath) (
    'Unowned matching junction must remain untouched.'
)
$LegacyPack = New-JunctionResource `
    -Path (Join-Path $GlobalRoot 'agents\skills\python') `
    -Target (Join-Path $Core 'packs\python') `
    -Owner 'projectD-core/global'
Invoke-GovernanceWiring `
    -Resources @($LegacyPack) `
    -Action Apply `
    -StatePath $GlobalState.StatePath | Out-Null
Assert-True (
    (Get-Item (Join-Path $GlobalRoot 'agents\skills\python')).LinkType -eq
        'Junction'
) 'Fixture must start with the legacy global pack junction.'
[Environment]::SetEnvironmentVariable('PROJECTD_CORE', $null, 'Process')
Invoke-GovernanceWiring `
    -Resources $GlobalState.Resources `
    -Action Apply `
    -StatePath $GlobalState.StatePath | Out-Null
$GlobalCheck = @(
    Invoke-GovernanceWiring `
        -Resources $GlobalState.Resources `
        -Action Check `
        -StatePath $GlobalState.StatePath
)
Assert-True (
    @($GlobalCheck | Where-Object { $_.State -ne $_.ExpectedState }).Count -eq 0
) 'Global desired state must be fully compliant after Apply.'
Assert-True (
    (Get-Item (Join-Path $GlobalRoot 'agents\skills\research')).LinkType -eq
        'Junction'
) 'Global desired state must expose core Skill junctions.'
Assert-True (
    -not (Test-Path (Join-Path $GlobalRoot 'agents\skills\python'))
) 'Global desired state must keep stack packs out of the global catalog.'
Assert-True (
    @($GlobalState.Resources | Where-Object {
        $_.Path -eq (Join-Path $GlobalRoot 'agents\skills\grill-me') -and
        $_.DesiredState -ceq 'Absent'
    }).Count -eq 1
) 'Global desired state must retire the merged grill-me alias.'
Invoke-GovernanceWiring `
    -Resources $GlobalState.Resources `
    -Action Remove `
    -StatePath $GlobalState.StatePath | Out-Null
$GlobalRemoved = @(
    Invoke-GovernanceWiring `
        -Resources $GlobalState.Resources `
        -Action Check `
        -StatePath $GlobalState.StatePath
)
Assert-True (
    @($GlobalRemoved | Where-Object State -NE 'Missing').Count -eq 0
) 'Global desired state must be fully missing after Remove.'

# Fleet resources use the same managed-block lifecycle.
$FleetProject = Join-Path $Root 'fleet-project'
New-Item -ItemType Directory -Path $FleetProject -Force | Out-Null
Set-Content `
    -LiteralPath (Join-Path $FleetProject 'AGENTS.md') `
    -Value 'project-owned prefix' `
    -Encoding utf8 `
    -NoNewline
Set-Content `
    -LiteralPath (Join-Path $FleetProject '.gitignore') `
    -Value "project-owned-ignore`n" `
    -Encoding utf8 `
    -NoNewline
$FleetItem = [pscustomobject]@{
    path = $FleetProject
    category = 'side'
    packs = @('python')
}
$InvalidFleetFailed = $false
try {
    New-FleetGovernanceWiring `
        -Core $Core `
        -FleetItems @([pscustomobject]@{
            path = $FleetProject
            category = 'side'
            packs = @('..\core\skills\research')
        }) `
        -StatePath (Join-Path $Root 'invalid-fleet-state.json') | Out-Null
} catch {
    $InvalidFleetFailed = $true
}
Assert-True $InvalidFleetFailed 'Fleet pack names must reject path traversal.'
$FleetState = New-FleetGovernanceWiring `
    -Core $Core `
    -FleetItems @($FleetItem) `
    -StatePath (Join-Path $Root 'fleet-state.json')
Assert-True (
    $FleetState.Resources.Count -eq 6
) 'Fleet desired state must include entries, .gitignore, and scoped pack links.'
Invoke-GovernanceWiring `
    -Resources $FleetState.Resources `
    -Action Apply `
    -StatePath $FleetState.StatePath | Out-Null
$FleetCheck = @(
    Invoke-GovernanceWiring `
        -Resources $FleetState.Resources `
        -Action Check `
        -StatePath $FleetState.StatePath
)
Assert-True (
    @($FleetCheck | Where-Object State -NE 'Compliant').Count -eq 0
) 'Fleet desired state must be fully compliant after Apply.'
Assert-True (
    (Get-Content -Raw (Join-Path $FleetProject 'AGENTS.md')).Contains(
        'project-owned prefix'
    )
) 'Fleet Apply must preserve project-owned entry content.'
$FleetGitIgnore = Get-Content -Raw (Join-Path $FleetProject '.gitignore')
Assert-True (
    $FleetGitIgnore.Contains('project-owned-ignore')
) 'Fleet Apply must preserve project-owned .gitignore content.'
foreach ($EntryPattern in @('/AGENTS.md', '/CLAUDE.md', '/GEMINI.md')) {
    Assert-True (
        $FleetGitIgnore.Contains($EntryPattern)
    ) "Fleet Apply must ignore $EntryPattern at the project root."
}
foreach ($ScopedSkill in @(
    '.agents\skills\python',
    '.claude\skills\python'
)) {
    $ScopedSkillPath = Join-Path $FleetProject $ScopedSkill
    Assert-True (
        (Get-Item $ScopedSkillPath).LinkType -eq 'Junction'
    ) "Fleet Apply must create scoped pack junction $ScopedSkill."
}
Assert-True (
    $FleetGitIgnore.Contains('/.agents/skills/python') -and
    $FleetGitIgnore.Contains('/.claude/skills/python')
) 'Fleet .gitignore must cover only the managed pack junctions.'

Write-Output 'GOVERNANCE_WIRING_CONTRACT_OK'
