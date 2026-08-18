[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Install', 'Check', 'Uninstall')]
    [string]$Mode,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GitDirectory
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
$adapterPath = Join-Path $root 'scripts\hooks\pre-push'
$ownershipMarker = 'projectD-core-owned-hook'

if ([string]::IsNullOrWhiteSpace($GitDirectory)) {
    $resolvedGitDirectory = (& git -C $root rev-parse --absolute-git-dir).Trim()
    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($resolvedGitDirectory)
    ) {
        throw 'Unable to resolve the repository Git directory.'
    }
    $GitDirectory = $resolvedGitDirectory
}
$gitRoot = [IO.Path]::GetFullPath($GitDirectory)
$hookDirectory = Join-Path $gitRoot 'hooks'
$targetPath = Join-Path $hookDirectory 'pre-push'

function Test-OwnedHook {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return (Get-Content -Raw -LiteralPath $Path).Contains($ownershipMarker)
}

switch ($Mode) {
    'Install' {
        if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
            throw "Tracked adapter is missing: $adapterPath"
        }
        if ($null -eq (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            throw 'PowerShell 7 is required before installing the hook.'
        }
        if (
            (Test-Path -LiteralPath $targetPath -PathType Leaf) -and
            -not (Test-OwnedHook -Path $targetPath)
        ) {
            throw "Refusing to overwrite an unowned hook: $targetPath"
        }
        New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null
        $adapterContent = Get-Content -Raw -LiteralPath $adapterPath
        $normalizedContent = ($adapterContent -replace '\r?\n', "`n")
        [IO.File]::WriteAllText(
            $targetPath,
            $normalizedContent,
            [Text.UTF8Encoding]::new($false)
        )
        if (-not $IsWindows) {
            & chmod +x -- $targetPath
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to make the hook executable: $targetPath"
            }
        }
        Write-Output "[PASS] Installed owned pre-push hook: $targetPath"
    }
    'Check' {
        if (-not (Test-OwnedHook -Path $targetPath)) {
            throw "Owned pre-push hook is missing: $targetPath"
        }
        $expected = (
            Get-Content -Raw -LiteralPath $adapterPath
        ) -replace '\r?\n', "`n"
        $actual = Get-Content -Raw -LiteralPath $targetPath
        if ($actual -cne $expected) {
            throw "Owned pre-push hook is stale: $targetPath"
        }
        Write-Output "[PASS] Owned pre-push hook is current: $targetPath"
    }
    'Uninstall' {
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Write-Output "[PASS] Pre-push hook is already absent: $targetPath"
            break
        }
        if (-not (Test-OwnedHook -Path $targetPath)) {
            throw "Refusing to remove an unowned hook: $targetPath"
        }
        Remove-Item -LiteralPath $targetPath -Force
        Write-Output "[PASS] Removed owned pre-push hook: $targetPath"
    }
}
