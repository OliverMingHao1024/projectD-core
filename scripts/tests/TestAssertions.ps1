# Shared assertion helper for scripts/tests/*.contract.ps1.
# Dot-source it: . (Join-Path $PSScriptRoot 'TestAssertions.ps1')
# Tests under core/skills/*/tests stay self-contained on purpose: skills are
# copied out on their own, so they must not depend on this file.

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
