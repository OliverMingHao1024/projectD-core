Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# GovernanceWiring is split by responsibility under governance-wiring/.
# Each part is dot-sourced into this module's scope, so private helpers stay
# private and callers keep importing only this file.
foreach ($part in @('resources', 'state', 'desired-state', 'inspection', 'mutation')) {
    . (Join-Path $PSScriptRoot "governance-wiring\$part.ps1")
}

function Resolve-ProjectDCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptRoot)

    if ($env:PROJECTD_CORE) {
        $candidate = Join-Path $env:PROJECTD_CORE 'core\constitution\rules.md'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:PROJECTD_CORE).Path
        }
    }
    $fromScript = [IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
    if (Test-Path -LiteralPath (
        Join-Path $fromScript 'core\constitution\rules.md'
    ) -PathType Leaf) {
        return $fromScript
    }
    throw 'Cannot resolve projectD-core root.'
}

Export-ModuleMember -Function @(
    'Resolve-ProjectDCore',
    'New-ManagedBlockResource',
    'New-FileCopyResource',
    'New-JunctionResource',
    'New-EnvironmentResource',
    'New-GlobalGovernanceWiring',
    'New-FleetGovernanceWiring',
    'Get-GovernanceWiringPlan',
    'Invoke-GovernanceWiring'
)
