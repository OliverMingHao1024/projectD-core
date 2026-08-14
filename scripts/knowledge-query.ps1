[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Query,
    [string]$System,
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\.local\knowledge-workspaces.json')
)

$ErrorActionPreference = 'Stop'
$registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$knowledgeRoot = $registry.workspaces.'projectd-knowledge'
if ([string]::IsNullOrWhiteSpace($knowledgeRoot)) {
    throw 'KnowledgeWorkspaceRegistry 缺少 projectd-knowledge。'
}

$queryScript = Join-Path $knowledgeRoot 'scripts\query.ps1'
$coreRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($System)) {
    & $queryScript -Query $Query -WorkspaceRoot $knowledgeRoot -CoreRoot $coreRoot -Json
} else {
    & $queryScript -Query $Query -System $System -WorkspaceRoot $knowledgeRoot -CoreRoot $coreRoot -Json
}
exit $LASTEXITCODE
