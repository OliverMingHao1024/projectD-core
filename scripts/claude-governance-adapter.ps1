[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$TrialsPath,
    [string]$CatalogPath,
    [string]$CatalogSchemaPath,
    [string]$TrialsSchemaPath,
    [string]$HostSchemaPath,
    [string]$CheckpointSchemaPath,
    [string]$OutputPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ModelId,
    [Parameter(Mandatory)][string]$ModelVersion,
    [string]$HarnessId = 'claude-manual-import-v1',
    [Parameter(Mandatory)][string]$StartedAt,
    [Parameter(Mandatory)][string]$CompletedAt,
    [string]$InputTokens = 'unavailable',
    [string]$OutputTokens = 'unavailable',
    [string]$CostUsd = 'unavailable',
    [Parameter(Mandatory)][int]$ApprovalCount,
    [Parameter(Mandatory)][string[]]$CompletedCriterion,
    [Parameter(Mandatory)][string[]]$RemainingCriterion,
    [Parameter(Mandatory)][string]$SmokeTestId,
    [Parameter(Mandatory)]
    [ValidateSet('passed', 'failed', 'not-run')]
    [string]$SmokeTestStatus,
    [switch]$CheckpointRead,
    [switch]$WorkspaceVerified,
    [switch]$AuthorizedManualImport,
    [switch]$ContractFixture,
    [string]$ClaudeVersionOverride,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot 'codex-governance-adapter.ps1'
$forward = @{
    ProjectRoot = $ProjectRoot
    HostName = 'claude'
    TrialsPath = $TrialsPath
    CatalogPath = $CatalogPath
    CatalogSchemaPath = $CatalogSchemaPath
    TrialsSchemaPath = $TrialsSchemaPath
    HostSchemaPath = $HostSchemaPath
    CheckpointSchemaPath = $CheckpointSchemaPath
    OutputPath = $OutputPath
    RunId = $RunId
    ModelId = $ModelId
    ModelVersion = $ModelVersion
    HarnessId = $HarnessId
    StartedAt = $StartedAt
    CompletedAt = $CompletedAt
    InputTokens = $InputTokens
    OutputTokens = $OutputTokens
    CostUsd = $CostUsd
    ApprovalCount = $ApprovalCount
    CompletedCriterion = $CompletedCriterion
    RemainingCriterion = $RemainingCriterion
    SmokeTestId = $SmokeTestId
    SmokeTestStatus = $SmokeTestStatus
    CheckpointRead = $CheckpointRead
    WorkspaceVerified = $WorkspaceVerified
    AuthorizedManualImport = $AuthorizedManualImport
    ContractFixture = $ContractFixture
    CliVersionOverride = $ClaudeVersionOverride
    Json = $Json
}

& $engine @forward
