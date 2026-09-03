[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    $script:checks++
    if ($Actual -cne $Expected) { $script:failures.Add("$Message (expected '$Expected', actual '$Actual')") }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('projectd-core-requirement-contract-' + [guid]::NewGuid().ToString('N'))
$knowledgeRoot = Join-Path $tempRoot 'knowledge'
[IO.Directory]::CreateDirectory((Join-Path $knowledgeRoot 'specs')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $knowledgeRoot 'scripts')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $knowledgeRoot 'templates\requirements')) | Out-Null
$registryPath = Join-Path $tempRoot 'registry.json'
try {
    [IO.File]::WriteAllText((Join-Path $knowledgeRoot 'specs\spec-source-and-evolution.md'), '# contract', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $knowledgeRoot 'templates\requirements\spec-amendment.md'), '# template', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $knowledgeRoot 'templates\requirements\debug-record.md'), '# template', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $knowledgeRoot 'scripts\register-spec.ps1'), @'
param($System, $FeatureId, $RequirementId, $SourcePath, $WorkspaceRoot)
[pscustomobject]@{
    delegated = $true
    system = $System
    feature_id = $FeatureId
    requirement_id = $RequirementId
    source_path = $SourcePath
    workspace_root = $WorkspaceRoot
}
'@, [Text.UTF8Encoding]::new($false))
    $registry = [ordered]@{ schema_version = 1; workspaces = [ordered]@{ 'projectd-knowledge' = $knowledgeRoot } }
    [IO.File]::WriteAllText($registryPath, ($registry | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))

    $adapter = Join-Path (Split-Path -Parent $PSScriptRoot) 'knowledge-requirement.ps1'
    $sourcePath = Join-Path $tempRoot 'source.docx'
    [IO.File]::WriteAllBytes($sourcePath, [byte[]]@(1, 2, 3))
    $newResult = & $adapter -Mode new -System projectd -FeatureId runtime-governance -RequirementId rg-001 -SourcePath $sourcePath -RegistryPath $registryPath
    Assert-True $newResult.delegated 'new intake delegates to the workspace-owned register script'
    Assert-Equal $newResult.workspace_root $knowledgeRoot 'adapter passes the resolved workspace root'

    $amend = & $adapter -Mode amend -System projectd -FeatureId runtime-governance -RequirementId rg-001 -RegistryPath $registryPath
    Assert-Equal $amend.specification_path (Join-Path $knowledgeRoot 'specs\spec-source-and-evolution.md') 'adapter reports the approved specification'
    Assert-Equal $amend.template_path (Join-Path $knowledgeRoot 'templates\requirements\spec-amendment.md') 'amend mode reports the workspace template'
    Assert-Equal $amend.requirement_root (Join-Path $knowledgeRoot 'requirements\projectd\runtime-governance\rg-001') 'amend mode reports the portable requirement location'

    $debug = & $adapter -Mode debug -System projectd -FeatureId runtime-governance -RequirementId rg-001 -RegistryPath $registryPath
    Assert-Equal $debug.template_path (Join-Path $knowledgeRoot 'templates\requirements\debug-record.md') 'debug mode reports the workspace template'

    $traversalBlocked = $false
    try { & $adapter -Mode debug -System '../outside' -RegistryPath $registryPath | Out-Null } catch {
        $traversalBlocked = $true
    }
    Assert-True $traversalBlocked 'portable identifiers reject path traversal'

    Remove-Item -LiteralPath (Join-Path $knowledgeRoot 'specs\spec-source-and-evolution.md') -Force
    $missingSpecBlocked = $false
    try { & $adapter -Mode debug -RegistryPath $registryPath | Out-Null } catch {
        $missingSpecBlocked = $_.Exception.Message -match 'approved requirement specification is unavailable'
    }
    Assert-True $missingSpecBlocked 'adapter fails closed when the approved workspace specification is missing'
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "$($failures.Count) of $checks knowledge requirement adapter checks failed."
}
Write-Output "$checks knowledge requirement adapter checks passed."
