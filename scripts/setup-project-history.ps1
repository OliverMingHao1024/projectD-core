[CmdletBinding()]
param(
    [string]$PythonPath,
    [string]$Wheelhouse,
    [string]$PackageIndexUrl,
    [string]$ModelSource,
    [switch]$AllowDownload,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

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
$LocalRoot = Join-Path $Core '.local\project-history'
$VenvRoot = Join-Path $LocalRoot '.venv'
$VenvPython = Join-Path $VenvRoot 'Scripts\python.exe'
$ModelRoot = Join-Path $LocalRoot 'models'
$LogRoot = Join-Path $LocalRoot 'logs'
$ConfigPath = Join-Path $LocalRoot 'projects.json'
$Requirements = Join-Path $Core 'core\skills\query-project-history\scripts\requirements.txt'
$HistoryScript = Join-Path $Core 'core\skills\query-project-history\scripts\history_search.py'
$ConfigTemplate = Join-Path $Core 'core\skills\query-project-history\assets\projects.example.json'

New-Item -ItemType Directory -Path $LocalRoot, $ModelRoot, $LogRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Copy-Item -LiteralPath $ConfigTemplate -Destination $ConfigPath
    Write-Host "已建立空白 allowlist：$ConfigPath" -ForegroundColor Green
}

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

$fastEmbedReady = & $VenvPython -c 'import importlib.util; raise SystemExit(0 if importlib.util.find_spec("fastembed") else 1)'
if ($LASTEXITCODE -ne 0) {
    if ($Wheelhouse) {
        $resolvedWheelhouse = (Resolve-Path -LiteralPath $Wheelhouse).Path
        Invoke-Checked -Executable $VenvPython -Arguments @(
            '-m', 'pip', 'install', '--no-index', '--find-links', $resolvedWheelhouse,
            '-r', $Requirements
        )
    } elseif ($PackageIndexUrl) {
        Invoke-Checked -Executable $VenvPython -Arguments @(
            '-m', 'pip', 'install', '--index-url', $PackageIndexUrl,
            '-r', $Requirements
        )
    } else {
        if (-not (Confirm-Download '缺少 FastEmbed，需要從 PyPI 下載固定版本套件')) {
            throw '缺少 FastEmbed；未取得下載授權。可改用 -Wheelhouse 或 -PackageIndexUrl。'
        }
        Invoke-Checked -Executable $VenvPython -Arguments @(
            '-m', 'pip', 'install', '-r', $Requirements
        )
    }
}

if ($ModelSource) {
    $resolvedModelSource = (Resolve-Path -LiteralPath $ModelSource).Path
    Copy-Item -Path (Join-Path $resolvedModelSource '*') -Destination $ModelRoot `
        -Recurse -Force
}

$modelFiles = Get-ChildItem -LiteralPath $ModelRoot -Recurse -File -ErrorAction SilentlyContinue
$modelDownloadApproved = $AllowDownload
if (-not $modelFiles) {
    if (-not (Confirm-Download '缺少本機多語 embedding model，需要從 Hugging Face 下載約 220MB')) {
        throw '缺少 embedding model；未取得下載授權。可改用 -ModelSource。'
    }
    $modelDownloadApproved = $true
}

$env:FASTEMBED_CACHE_PATH = $ModelRoot
if (-not $modelDownloadApproved) {
    $env:HF_HUB_OFFLINE = '1'
}
$prepareArguments = @($HistoryScript, 'prepare', '--cache-dir', $ModelRoot)
if ($modelDownloadApproved) {
    $prepareArguments += '--allow-download'
}
Invoke-Checked -Executable $VenvPython -Arguments $prepareArguments

Write-Host ''
Write-Host 'Project history 本機環境已就緒。' -ForegroundColor Cyan
Write-Host "設定 allowlist：$ConfigPath"
Write-Host '查看狀態：.\scripts\project-history.ps1 status'
Write-Host '建立索引：.\scripts\project-history.ps1 rebuild'
