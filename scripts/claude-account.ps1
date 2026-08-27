[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Status', 'Prepare', 'Verify')]
    [string]$Action,
    [string]$Target,
    [string]$ProfilesPath
)

$ErrorActionPreference = 'Stop'
$entrypoint = Join-Path $PSScriptRoot (
    '..\core\skills\claude-switch-account\scripts\claude-account.ps1'
)
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
    throw 'The canonical Claude account entrypoint is unavailable.'
}

& $entrypoint @PSBoundParameters
