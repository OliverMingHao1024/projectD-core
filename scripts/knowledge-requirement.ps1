[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('new', 'amend', 'debug')][string]$Mode,
    [string]$System,
    [string]$FeatureId,
    [string]$RequirementId,
    [string]$SourcePath,
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\.local\knowledge-workspaces.json')
)

$ErrorActionPreference = 'Stop'
$registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$knowledgeRoot = [string]$registry.workspaces.'projectd-knowledge'
if ([string]::IsNullOrWhiteSpace($knowledgeRoot) -or -not (Test-Path -LiteralPath $knowledgeRoot -PathType Container)) {
    throw 'KnowledgeWorkspaceRegistry cannot resolve projectd-knowledge.'
}

if ($Mode -eq 'new') {
    foreach ($required in @('System', 'FeatureId', 'RequirementId', 'SourcePath')) {
        if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $required -ValueOnly))) {
            throw "$required is required for new requirement intake."
        }
    }
    & (Join-Path $knowledgeRoot 'scripts\register-spec.ps1') `
        -System $System `
        -FeatureId $FeatureId `
        -RequirementId $RequirementId `
        -SourcePath $SourcePath `
        -WorkspaceRoot $knowledgeRoot
    return
}

[pscustomobject]@{
    mode = $Mode
    workspace_root = $knowledgeRoot
    system = $System
    feature_id = $FeatureId
    requirement_id = $RequirementId
    next_step = if ($Mode -eq 'amend') { 'Create the next SpecAmendment candidate from the workspace template.' } else { 'Create a DebugRecord candidate and link an Amendment only if expected behavior changed.' }
}
