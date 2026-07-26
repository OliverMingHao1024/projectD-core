[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('status', 'rebuild', 'update', 'query')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Text,

    [string]$Project,
    [ValidateRange(1, 50)]
    [int]$Limit = 5
)

$ErrorActionPreference = 'Stop'
$Started = Get-Date
$Succeeded = $false
$ErrorType = $null

function Rotate-OperationLogs {
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory)) {
        return
    }
    $cutoff = (Get-Date).AddDays(-7)
    Get-ChildItem -LiteralPath $Directory -Filter '*.jsonl' -File |
        Where-Object LastWriteTime -LT $cutoff |
        Remove-Item -Force

    $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.jsonl' -File |
        Sort-Object LastWriteTime)
    $total = ($files | Measure-Object Length -Sum).Sum
    while ($files.Count -gt 1 -and $total -gt 10MB) {
        $oldest = $files[0]
        $total -= $oldest.Length
        Remove-Item -LiteralPath $oldest.FullName -Force
        $files = @($files | Select-Object -Skip 1)
    }
}

function Write-OperationLog {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][bool]$Success,
        [string]$FailureType
    )

    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    $record = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        command = $Operation
        success = $Success
        elapsed_ms = [math]::Round(((Get-Date) - $Started).TotalMilliseconds)
        error_type = $FailureType
    }
    $logName = "$(Get-Date -Format 'yyyy-MM-dd-HHmmss-fffffff')-$PID.jsonl"
    $record | ConvertTo-Json -Compress |
        Set-Content -LiteralPath (Join-Path $LogRoot $logName) `
            -Encoding utf8
    Rotate-OperationLogs -Directory $LogRoot
}

function Invoke-HistoryPython {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & $VenvPython $HistoryScript @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "project history command failed (exit $LASTEXITCODE)"
    }
}

function Read-Allowlist {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "找不到 allowlist：$ConfigPath。請先執行 setup-project-history.ps1。"
    }
    $configuration = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
    if ($configuration.schema_version -ne 1) {
        throw "不支援的 projects.json schema_version：$($configuration.schema_version)"
    }
    return @($configuration.projects)
}

function Update-AllowlistedProjects {
    param([Parameter(Mandatory)][object[]]$Projects)

    foreach ($entry in $Projects) {
        if (-not $entry.name -or -not $entry.path) {
            throw 'allowlist 每個項目都必須包含 name 與 path。'
        }
        $projectPath = [IO.Path]::GetFullPath([string]$entry.path)
        if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
            throw "allowlist 專案不存在：$projectPath"
        }
        $directoryName = Split-Path $projectPath.TrimEnd('\') -Leaf
        if (-not [string]::Equals(
            [string]$entry.name,
            $directoryName,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "allowlist name 必須等於專案資料夾名稱：$directoryName"
        }
        $arguments = @(
            $HistoryScript, 'index',
            '--db', $DatabasePath,
            '--project', $projectPath,
            '--mode', 'hybrid'
        )
        if ($entry.include_auxiliary -eq $true) {
            $arguments += '--include-auxiliary'
        }
        & $VenvPython @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "索引專案失敗：$($entry.name)"
        }
    }
}

$Core = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LocalRoot = Join-Path $Core '.local\project-history'
$VenvPython = Join-Path $LocalRoot '.venv\Scripts\python.exe'
$ModelRoot = Join-Path $LocalRoot 'models'
$LogRoot = Join-Path $LocalRoot 'logs'
$ConfigPath = Join-Path $LocalRoot 'projects.json'
$DatabasePath = Join-Path $LocalRoot 'index.db'
$HistoryScript = Join-Path $Core 'core\skills\query-project-history\scripts\history_search.py'
$env:FASTEMBED_CACHE_PATH = $ModelRoot

try {
    if ($Command -eq 'status' -and -not (Test-Path -LiteralPath $VenvPython)) {
        Write-Host 'Project history 尚未安裝。'
        Write-Host '執行：.\scripts\setup-project-history.ps1'
        $Succeeded = $true
        return
    }
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        throw '找不到專用 Python 環境；請先執行 setup-project-history.ps1。'
    }

    switch ($Command) {
        'status' {
            Invoke-HistoryPython -Arguments @('status', '--db', $DatabasePath)
            if (Test-Path -LiteralPath $ConfigPath) {
                $projects = Read-Allowlist
                Write-Host "Allowlist 專案數：$($projects.Count)"
                Write-Host "設定檔：$ConfigPath"
            }
        }
        'rebuild' {
            $projects = Read-Allowlist
            if (-not $projects) {
                throw "allowlist 是空的；請先編輯 $ConfigPath"
            }
            $resolvedDatabase = [IO.Path]::GetFullPath($DatabasePath)
            if (-not $resolvedDatabase.StartsWith(
                [IO.Path]::GetFullPath($LocalRoot),
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw "不安全的 index 路徑：$resolvedDatabase"
            }
            foreach ($derivedFile in @(
                $resolvedDatabase,
                "$resolvedDatabase-wal",
                "$resolvedDatabase-shm"
            )) {
                if (Test-Path -LiteralPath $derivedFile) {
                    Remove-Item -LiteralPath $derivedFile -Force
                }
            }
            Update-AllowlistedProjects -Projects $projects
            Invoke-HistoryPython -Arguments @('status', '--db', $DatabasePath)
        }
        'update' {
            $projects = Read-Allowlist
            if (-not $projects) {
                throw "allowlist 是空的；請先編輯 $ConfigPath"
            }
            Update-AllowlistedProjects -Projects $projects
            Invoke-HistoryPython -Arguments @('status', '--db', $DatabasePath)
        }
        'query' {
            if ([string]::IsNullOrWhiteSpace($Text)) {
                $Text = Read-Host '請輸入查詢（輸入內容不會寫入 project-history log）'
            }
            if ([string]::IsNullOrWhiteSpace($Text)) {
                throw '查詢文字不可為空。'
            }
            if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
                throw '索引尚未建立；請先執行 rebuild。'
            }
            $arguments = @(
                'query', '--db', $DatabasePath, '--query', $Text,
                '--mode', 'hybrid', '--limit', [string]$Limit
            )
            if ($Project) {
                $arguments += @('--project', $Project)
            }
            Invoke-HistoryPython -Arguments $arguments
        }
    }
    $Succeeded = $true
} catch {
    $ErrorType = $_.Exception.GetType().Name
    Write-Error $_
    exit 1
} finally {
    Write-OperationLog -Operation $Command -Success $Succeeded -FailureType $ErrorType
}
