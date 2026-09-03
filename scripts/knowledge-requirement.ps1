[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('new', 'amend', 'debug')][string]$Mode,
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$System,
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$FeatureId,
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$RequirementId,
    [string]$SourcePath,
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\.local\knowledge-workspaces.json')
)

$ErrorActionPreference = 'Stop'
$registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$knowledgeRoot = [string]$registry.workspaces.'projectd-knowledge'
if ([string]::IsNullOrWhiteSpace($knowledgeRoot) -or -not (Test-Path -LiteralPath $knowledgeRoot -PathType Container)) {
    throw 'KnowledgeWorkspaceRegistry cannot resolve projectd-knowledge.'
}
$knowledgeRoot = [IO.Path]::GetFullPath($knowledgeRoot)
$specificationPath = Join-Path $knowledgeRoot 'specs\spec-source-and-evolution.md'
if (-not (Test-Path -LiteralPath $specificationPath -PathType Leaf)) {
    throw "KnowledgeWorkspace approved requirement specification is unavailable: $specificationPath"
}

if ($Mode -eq 'new') {
    foreach ($required in @('System', 'FeatureId', 'RequirementId', 'SourcePath')) {
        if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $required -ValueOnly))) {
            throw "$required is required for new requirement intake."
        }
    }
    $registerScript = Join-Path $knowledgeRoot 'scripts\register-spec.ps1'
    if (-not (Test-Path -LiteralPath $registerScript -PathType Leaf)) {
        throw "KnowledgeWorkspace requirement intake script is unavailable: $registerScript"
    }
    & $registerScript `
        -System $System `
        -FeatureId $FeatureId `
        -RequirementId $RequirementId `
        -SourcePath $SourcePath `
        -WorkspaceRoot $knowledgeRoot
    return
}

$templateName = if ($Mode -eq 'amend') { 'spec-amendment.md' } else { 'debug-record.md' }
$templatePath = Join-Path $knowledgeRoot "templates\requirements\$templateName"
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "KnowledgeWorkspace requirement template is unavailable: $templatePath"
}
$requirementRoot = if (
    -not [string]::IsNullOrWhiteSpace($System) -and
    -not [string]::IsNullOrWhiteSpace($FeatureId) -and
    -not [string]::IsNullOrWhiteSpace($RequirementId)
) {
    Join-Path $knowledgeRoot "requirements\$System\$FeatureId\$RequirementId"
} else { $null }

[pscustomobject]@{
    mode = $Mode
    workspace_root = $knowledgeRoot
    system = $System
    feature_id = $FeatureId
    requirement_id = $RequirementId
    specification_path = $specificationPath
    template_path = $templatePath
    requirement_root = $requirementRoot
    next_step = if ($Mode -eq 'amend') { 'Create the next SpecAmendment candidate from the workspace template.' } else { 'Create a DebugRecord candidate and link an Amendment only if expected behavior changed.' }
}
