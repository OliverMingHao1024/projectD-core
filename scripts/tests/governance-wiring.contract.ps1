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
    @($GlobalCheck | Where-Object State -NE 'Compliant').Count -eq 0
) 'Global desired state must be fully compliant after Apply.'
Assert-True (
    (Get-Item (Join-Path $GlobalRoot 'agents\skills\python')).LinkType -eq
        'Junction'
) 'Global desired state must create skill junctions.'
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
$FleetItem = [pscustomobject]@{
    path = $FleetProject
    category = 'side'
    packs = @('python')
}
$FleetState = New-FleetGovernanceWiring `
    -Core $Core `
    -FleetItems @($FleetItem) `
    -StatePath (Join-Path $Root 'fleet-state.json')
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

Write-Output 'GOVERNANCE_WIRING_CONTRACT_OK'
