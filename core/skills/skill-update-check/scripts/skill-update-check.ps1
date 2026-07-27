[CmdletBinding()]
param(
    [string]$RegistryPath,
    [string]$CandidateId,
    [string]$FixturePath
)

$ErrorActionPreference = 'Stop'
$SkillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Core = [IO.Path]::GetFullPath((Join-Path $SkillRoot '..\..\..'))
$ScoutScript = Join-Path $Core 'core\skills\skill-scout\scripts\skill-scout.ps1'
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $Core 'vault\governance\skill-registry.json'
}

$registry = Get-Content -Raw -LiteralPath $RegistryPath | ConvertFrom-Json
$sources = @{}
foreach ($source in @($registry.sources)) {
    $sources[[string]$source.id] = $source
}
$candidates = @(
    $registry.candidates |
        Where-Object lifecycle_status -EQ 'adopted' |
        Where-Object {
            [string]::IsNullOrWhiteSpace($CandidateId) -or
            $_.id -eq $CandidateId
        }
)

$unchanged = [Collections.Generic.List[object]]::new()
$updates = [Collections.Generic.List[object]]::new()
$errors = [Collections.Generic.List[object]]::new()

foreach ($candidate in $candidates) {
    if (-not $sources.ContainsKey([string]$candidate.source_id)) {
        $errors.Add([pscustomobject]@{
            id = $candidate.id
            reason = 'Registry source_id does not exist.'
        })
        continue
    }
    $source = $sources[[string]$candidate.source_id]
    $sourceIdentity = "$($source.repository)/$($candidate.source_path)"
    try {
        $arguments = @{
            Source = $sourceIdentity
        }
        if ($FixturePath) {
            $arguments.FixturePath = $FixturePath
        }
        $result = & $ScoutScript @arguments | ConvertFrom-Json
        if (@($result.candidates).Count -ne 1) {
            $reason = if (@($result.rejections).Count -gt 0) {
                (@($result.rejections[0].reasons) -join '; ')
            } else {
                'Upstream Skill path was not found.'
            }
            throw $reason
        }
        $current = $result.candidates[0]
        $record = [pscustomobject]@{
            id = $candidate.id
            source = $sourceIdentity
            old_commit = $candidate.observed_commit
            new_commit = $current.commit
            old_digest = $candidate.upstream_digest
            new_digest = $current.content_digest
        }
        if ($candidate.upstream_digest -eq $current.content_digest) {
            $unchanged.Add($record)
        } else {
            $updates.Add($record)
        }
    } catch {
        $errors.Add([pscustomobject]@{
            id = $candidate.id
            source = $sourceIdentity
            reason = $_.Exception.Message
        })
    }
}

[pscustomobject]@{
    schema_version = 1
    mutated = $false
    checked = $candidates.Count
    unchanged = $unchanged.ToArray()
    updates = $updates.ToArray()
    errors = $errors.ToArray()
} | ConvertTo-Json -Depth 8
