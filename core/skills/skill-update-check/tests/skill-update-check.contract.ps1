[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$SkillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Core = [IO.Path]::GetFullPath((Join-Path $SkillRoot '..\..\..'))
$Script = Join-Path $SkillRoot 'scripts\skill-update-check.ps1'
$Fixture = Join-Path $Core 'core\skills\skill-scout\tests\fixtures\candidates.json'
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "skill-update-check-$PID"
$Registry = Join-Path $TempRoot 'registry.json'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    $data = [pscustomobject]@{
        schema_version = 1
        sources = @(
            [pscustomobject]@{
                id = 'github-mattpocock-skills'
                provider = 'github'
                repository = 'mattpocock/skills'
            },
            [pscustomobject]@{
                id = 'skill-vault-ali'
                provider = 'skill-vault'
                repository = 'skill-vault/ali'
            }
        )
        candidates = @(
            [pscustomobject]@{
                id = 'mattpocock-skills--skills-engineering-grill-with-docs'
                source_id = 'github-mattpocock-skills'
                source_path = 'skills/engineering/grill-with-docs'
                observed_commit = 'old'
                upstream_digest = 'sha256:old'
                lifecycle_status = 'adopted'
            },
            [pscustomobject]@{
                id = 'skill-vault-ali--tfs-code'
                source_id = 'skill-vault-ali'
                source_path = 'tfs-code'
                observed_commit = $null
                upstream_digest = 'sha256:internal'
                lifecycle_status = 'adopted'
            }
        )
    }
    $data | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $Registry -Encoding utf8
    $result = & $Script `
        -RegistryPath $Registry `
        -FixturePath $Fixture |
        ConvertFrom-Json
    Assert-True (-not $result.mutated) 'Update check must be read-only.'
    Assert-True ($result.checked -eq 1) 'One adopted candidate must be checked.'
    Assert-True (
        @($result.updates).Count -eq 1
    ) 'A changed upstream digest must be reported.'
    Assert-True (
        @($result.errors).Count -eq 0
    ) 'Fixture check must not report errors.'
    Assert-True (
        @($result.skipped).Count -eq 1
    ) 'A non-GitHub provider must be reported as skipped.'
    Assert-True (
        $result.skipped[0].id -eq 'skill-vault-ali--tfs-code'
    ) 'The Skill Vault candidate must be the skipped record.'
    Write-Output 'SKILL_UPDATE_CHECK_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}
