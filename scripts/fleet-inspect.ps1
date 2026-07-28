[CmdletBinding()]
param(
    [string]$FleetPath = (
        Join-Path (Split-Path -Parent $PSScriptRoot) 'fleet\fleet.json'
    ),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$core = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$issues = [Collections.Generic.List[object]]::new()
$projects = [Collections.Generic.List[object]]::new()

function Add-InspectionIssue {
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][string]$Path
    )

    $script:issues.Add([pscustomobject]@{
        code = $Code
        message = $Message
        path = $Path
    })
}

function Write-InspectionResult {
    param([Parameter(Mandatory)][object]$Result)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 8
        return
    }

    foreach ($project in @($Result.projects)) {
        $state = if ($project.exists) { 'FOUND' } else { 'MISSING' }
        Write-Output (
            "[$state] $($project.path) " +
            "(category: $($project.category); packs: " +
            "$(@($project.packs) -join ', '))"
        )
        foreach ($entry in @($project.entry_targets)) {
            $entryState = if ($entry.exists) { 'present' } else { 'absent' }
            Write-Output "  [$entryState] $($entry.path)"
        }
    }
    foreach ($issue in @($Result.issues)) {
        Write-Output "[ISSUE] $($issue.code): $($issue.message)"
    }
    Write-Output (
        "Summary: $(@($Result.projects).Count) project(s), " +
        "$(@($Result.issues).Count) issue(s)."
    )
}

$resolvedFleetPath = [IO.Path]::GetFullPath($FleetPath)
$fleetDirectory = Split-Path -Parent $resolvedFleetPath
[object[]]$items = @()

if (-not (Test-Path -LiteralPath $resolvedFleetPath -PathType Leaf)) {
    Add-InspectionIssue `
        -Code 'fleet-file-missing' `
        -Message "Fleet file not found: $resolvedFleetPath" `
        -Path $resolvedFleetPath
} else {
    try {
        $items = @(
            Get-Content -Raw -LiteralPath $resolvedFleetPath |
                ConvertFrom-Json |
                ForEach-Object { $_ }
        )
        if ($items.Count -eq 0) {
            Add-InspectionIssue `
                -Code 'fleet-empty' `
                -Message 'Fleet file contains no projects.' `
                -Path $resolvedFleetPath
        }
    } catch {
        Add-InspectionIssue `
            -Code 'fleet-json-invalid' `
            -Message "Fleet JSON is invalid: $($_.Exception.Message)" `
            -Path $resolvedFleetPath
    }
}

$seenPaths = @{}
foreach ($item in $items) {
    $configuredPath = [string]$item.path
    if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        Add-InspectionIssue `
            -Code 'project-path-empty' `
            -Message 'Fleet project path is empty.' `
            -Path $null
        continue
    }

    $projectPath = if ([IO.Path]::IsPathRooted($configuredPath)) {
        [IO.Path]::GetFullPath($configuredPath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $fleetDirectory $configuredPath))
    }
    $pathKey = $projectPath.TrimEnd('\').ToLowerInvariant()
    if ($seenPaths.ContainsKey($pathKey)) {
        Add-InspectionIssue `
            -Code 'project-path-duplicate' `
            -Message "Fleet project path is duplicated: $projectPath" `
            -Path $projectPath
        continue
    }
    $seenPaths[$pathKey] = $true

    $exists = Test-Path -LiteralPath $projectPath -PathType Container
    if (-not $exists) {
        Add-InspectionIssue `
            -Code 'project-directory-missing' `
            -Message "Project directory is missing: $projectPath" `
            -Path $projectPath
    }

    $category = [string]$item.category
    if ($category -notin @('work', 'side')) {
        Add-InspectionIssue `
            -Code 'project-category-invalid' `
            -Message "Project category must be work or side: $projectPath" `
            -Path $projectPath
    }

    $packs = @(
        @($item.packs) |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            } |
            ForEach-Object { [string]$_ }
    )
    foreach ($pack in $packs) {
        $packPath = Join-Path $core "packs\$pack\SKILL.md"
        if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
            Add-InspectionIssue `
                -Code 'project-pack-missing' `
                -Message "Canonical pack is missing: $pack" `
                -Path $packPath
        }
    }

    $entryTargets = @(
        foreach ($entryName in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')) {
            $entryPath = Join-Path $projectPath $entryName
            [pscustomobject]@{
                path = $entryPath
                exists = Test-Path -LiteralPath $entryPath -PathType Leaf
            }
        }
    )
    $projects.Add([pscustomobject]@{
        path = $projectPath
        category = $category
        packs = $packs
        exists = $exists
        entry_targets = $entryTargets
    })
}

$result = [pscustomobject]@{
    schema_version = 1
    passed = $issues.Count -eq 0
    scan_scope = 'fleet-config-only'
    source_content_scanned = $false
    fleet_path = $resolvedFleetPath
    projects = $projects.ToArray()
    issues = $issues.ToArray()
}
Write-InspectionResult $result
if (-not $result.passed) {
    exit 1
}
