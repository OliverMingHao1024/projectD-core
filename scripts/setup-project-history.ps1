[CmdletBinding()]
param(
    [string]$PythonPath,
    [string]$Wheelhouse,
    [string]$PackageIndexUrl,
    [string]$ModelSource,
    [ValidateSet('lexical', 'hybrid')]
    [string]$Mode,
    [switch]$AllowDownload,
    [switch]$NonInteractive,
    [string]$RuntimeRoot
)

$ErrorActionPreference = 'Stop'

function Assert-SafePackageIndexUrl {
    param([Parameter(Mandatory)][string]$Value)

    $uri = $null
    if (
        -not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne [Uri]::UriSchemeHttps
    ) {
        throw 'PackageIndexUrl must be an absolute HTTPS URL.'
    }
    if (
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)
    ) {
        throw 'PackageIndexUrl must not contain embedded credentials.'
    }
}

function Confirm-Download {
    param([Parameter(Mandatory)][string]$Description)

    if ($AllowDownload) {
        return $true
    }
    if ($NonInteractive) {
        return $false
    }
    $answer = Read-Host "$Description。是否允許下載？[y/N]"
    return $answer -match '^(?i:y|yes)$'
}

function Resolve-PythonExecutable {
    if ($PythonPath) {
        if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
            throw "指定的 Python 不存在：$PythonPath"
        }
        return (Resolve-Path -LiteralPath $PythonPath).Path
    }

    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $knownPath = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'
    if (Test-Path -LiteralPath $knownPath -PathType Leaf) {
        return $knownPath
    }

    if (-not (Confirm-Download '未找到 Python 3.11+，需要透過 winget 安裝 Python 3.11')) {
        throw '缺少 Python 3.11+；未取得下載授權。請由公司 IT 提供 Python 或使用 -PythonPath。'
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw '未找到 winget。請由公司 IT 安裝 Python 3.11+，再以 -PythonPath 指定。'
    }
    & winget install --id Python.Python.3.11 --exact `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Python 安裝失敗（exit $LASTEXITCODE）。"
    }
    if (-not (Test-Path -LiteralPath $knownPath -PathType Leaf)) {
        throw 'Python 已安裝但目前程序找不到執行檔；請重開終端後重跑。'
    }
    return $knownPath
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable 執行失敗（exit $LASTEXITCODE）。"
    }
}

$Core = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LocalRoot = if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    Join-Path $Core '.local\project-history'
} else {
    [IO.Path]::GetFullPath($RuntimeRoot)
}
$VenvRoot = Join-Path $LocalRoot '.venv'
$VenvPython = Join-Path $VenvRoot 'Scripts\python.exe'
$ModelRoot = Join-Path $LocalRoot 'models'
$ConfigPath = Join-Path $LocalRoot 'projects.json'
$Requirements = Join-Path $Core 'core\skills\query-project-history\scripts\requirements.txt'
$HistoryScript = Join-Path $Core 'core\skills\query-project-history\scripts\history_search.py'
$CliScript = Join-Path $Core 'core\skills\query-project-history\scripts\project_history_cli.py'
$ModelVerifier = Join-Path $Core 'core\skills\query-project-history\scripts\model_manifest.py'
$ModelManifest = Join-Path $Core 'core\skills\query-project-history\scripts\model-manifest.json'
$RuntimeConfig = Join-Path $LocalRoot 'runtime.json'

if ($PackageIndexUrl) {
    Assert-SafePackageIndexUrl $PackageIndexUrl
}

New-Item -ItemType Directory -Path $LocalRoot, $ModelRoot -Force | Out-Null

if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
    $Python = Resolve-PythonExecutable
    $versionText = & $Python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
    if ($LASTEXITCODE -ne 0) {
        throw '無法確認 Python 版本。'
    }
    $version = [version]$versionText.Trim()
    if ($version -lt [version]'3.11') {
        throw "需要 Python 3.11+，目前為 $version。"
    }
    Invoke-Checked -Executable $Python -Arguments @('-m', 'venv', $VenvRoot)
}

$EffectiveMode = if ($PSBoundParameters.ContainsKey('Mode')) {
    $Mode
} elseif (Test-Path -LiteralPath $RuntimeConfig -PathType Leaf) {
    [string](Get-Content -Raw -LiteralPath $RuntimeConfig | ConvertFrom-Json).mode
} else {
    'hybrid'
}
if ($EffectiveMode -notin @('lexical', 'hybrid')) {
    throw "不支援的既有 runtime mode：$EffectiveMode"
}

if ($EffectiveMode -eq 'hybrid') {
    $hybridPlatform = & $VenvPython -c (
        'import json,platform,sys; print(json.dumps({' +
        '"version":[sys.version_info.major,sys.version_info.minor],' +
        '"machine":platform.machine(),"system":platform.system()}))'
    ) | ConvertFrom-Json
    if (
        @($hybridPlatform.version)[0] -ne 3 -or
        @($hybridPlatform.version)[1] -ne 11 -or
        [string]$hybridPlatform.system -ne 'Windows' -or
        [string]$hybridPlatform.machine -notin @('AMD64', 'x86_64')
    ) {
        throw (
            'Hybrid mode lock file supports only CPython 3.11 on ' +
            'Windows x86-64. Use -Mode lexical on other platforms.'
        )
    }
    $fastEmbedReady = & $VenvPython -c 'import importlib.util; raise SystemExit(0 if importlib.util.find_spec("fastembed") else 1)'
    if ($LASTEXITCODE -ne 0) {
        if ($Wheelhouse) {
            $resolvedWheelhouse = (Resolve-Path -LiteralPath $Wheelhouse).Path
            Invoke-Checked -Executable $VenvPython -Arguments @(
                '-m', 'pip', 'install', '--require-hashes',
                '--no-index', '--find-links', $resolvedWheelhouse,
                '-r', $Requirements
            )
        } elseif ($PackageIndexUrl) {
            Invoke-Checked -Executable $VenvPython -Arguments @(
                '-m', 'pip', 'install', '--require-hashes',
                '--index-url', $PackageIndexUrl,
                '-r', $Requirements
            )
        } else {
            if (-not (Confirm-Download '缺少 FastEmbed，需要從 PyPI 下載固定版本套件')) {
                throw '缺少 FastEmbed；未取得下載授權。可改用 -Wheelhouse 或 -PackageIndexUrl。'
            }
            Invoke-Checked -Executable $VenvPython -Arguments @(
                '-m', 'pip', 'install', '--require-hashes', '-r', $Requirements
            )
        }
    }

    if ($ModelSource) {
        $resolvedModelSource = (Resolve-Path -LiteralPath $ModelSource).Path
        Copy-Item -Path (Join-Path $resolvedModelSource '*') -Destination $ModelRoot `
            -Recurse -Force
    }

    $modelFiles = Get-ChildItem -LiteralPath $ModelRoot -Recurse -File `
        -ErrorAction SilentlyContinue
    $modelDownloadApproved = $AllowDownload
    if (-not $modelFiles) {
        if (-not (Confirm-Download '缺少本機多語 embedding model，需要從 Hugging Face 下載約 220MB')) {
            throw '缺少 embedding model；未取得下載授權。可改用 -ModelSource。'
        }
        $modelDownloadApproved = $true
    }

    $env:FASTEMBED_CACHE_PATH = $ModelRoot
    if ($modelFiles) {
        $verificationOutput = @(
            & $VenvPython $ModelVerifier `
                --cache-root $ModelRoot `
                --manifest $ModelManifest 2>&1
        )
        if ($LASTEXITCODE -ne 0) {
            if (-not $modelDownloadApproved) {
                throw (
                    'Existing embedding model failed manifest verification. ' +
                    ($verificationOutput -join ' ')
                )
            }
            $manifest = Get-Content -Raw -LiteralPath $ModelManifest |
                ConvertFrom-Json
            $managedCache = [IO.Path]::GetFullPath(
                (Join-Path $ModelRoot ([string]$manifest.cache_path))
            )
            $modelBoundary = [IO.Path]::GetFullPath($ModelRoot).TrimEnd('\') + '\'
            if (-not $managedCache.StartsWith(
                $modelBoundary,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw 'Model manifest cache_path escapes the managed model root.'
            }
            if (Test-Path -LiteralPath $managedCache -PathType Container) {
                Remove-Item -LiteralPath $managedCache -Recurse -Force
            }
        }
    }
    if (-not $modelDownloadApproved) {
        $env:HF_HUB_OFFLINE = '1'
    }
    if ($modelDownloadApproved) {
        Invoke-Checked -Executable $VenvPython -Arguments @(
            $ModelVerifier,
            '--cache-root', $ModelRoot,
            '--manifest', $ModelManifest,
            '--download'
        )
    }
    $env:HF_HUB_OFFLINE = '1'
    Invoke-Checked -Executable $VenvPython -Arguments @(
        $HistoryScript,
        'prepare',
        '--cache-dir', $ModelRoot
    )
    Invoke-Checked -Executable $VenvPython -Arguments @(
        $ModelVerifier,
        '--cache-root', $ModelRoot,
        '--manifest', $ModelManifest
    )
}

Invoke-Checked -Executable $VenvPython -Arguments @(
    $CliScript,
    '--core-root', $Core,
    '--runtime-root', $LocalRoot,
    'mode', $EffectiveMode
)
Invoke-Checked -Executable $VenvPython -Arguments @(
    $CliScript,
    '--core-root', $Core,
    '--runtime-root', $LocalRoot,
    'status'
)

Write-Host ''
Write-Host 'Project history 本機環境已就緒。' -ForegroundColor Cyan
Write-Host "Mode：$EffectiveMode"
Write-Host "設定 allowlist：$ConfigPath"
Write-Host '管理 allowlist：.\scripts\project-history.ps1 project list'
Write-Host '查看狀態：.\scripts\project-history.ps1 status'
Write-Host '建立索引：.\scripts\project-history.ps1 rebuild'
