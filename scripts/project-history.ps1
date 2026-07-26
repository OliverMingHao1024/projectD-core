[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet(
        'status', 'rebuild', 'update', 'query', 'project', 'candidate', 'mode'
    )]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Text,

    [Parameter(Position = 2)]
    [string]$Value,

    [string]$Project,
    [ValidateRange(1, 50)]
    [int]$Limit = 5,
    [switch]$IncludeAuxiliary,
    [switch]$Yes,
    [string]$RecordPath,
    [string]$RuntimeRoot
)

$ErrorActionPreference = 'Stop'

function Invoke-HistoryRuntime {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & $VenvPython $CliScript `
        '--core-root' $Core `
        '--runtime-root' $LocalRoot `
        @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "project history command failed (exit $LASTEXITCODE)"
    }
}

function Confirm-Mutation {
    param([Parameter(Mandatory)][string]$Description)

    Write-Host $Description -ForegroundColor Yellow
    if ($Yes) {
        return
    }
    $answer = Read-Host '是否套用此變更？[y/N]'
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw '變更未獲確認。'
    }
}

$Core = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LocalRoot = if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    Join-Path $Core '.local\project-history'
} else {
    [IO.Path]::GetFullPath($RuntimeRoot)
}
$VenvPython = Join-Path $LocalRoot '.venv\Scripts\python.exe'
$CliScript = Join-Path $Core `
    'core\skills\query-project-history\scripts\project_history_cli.py'

try {
    if ($Command -eq 'status' -and -not (Test-Path -LiteralPath $VenvPython)) {
        Write-Host 'Project history 尚未安裝。'
        Write-Host '執行：.\scripts\setup-project-history.ps1'
        return
    }
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        throw '找不到專用 Python 環境；請先執行 setup-project-history.ps1。'
    }

    switch ($Command) {
        'status' {
            Invoke-HistoryRuntime -Arguments @('status')
        }
        'rebuild' {
            Invoke-HistoryRuntime -Arguments @('rebuild')
        }
        'update' {
            Invoke-HistoryRuntime -Arguments @('update')
        }
        'query' {
            if ([string]::IsNullOrWhiteSpace($Text)) {
                $Text = Read-Host '請輸入查詢（輸入內容不會寫入 project-history log）'
            }
            if ([string]::IsNullOrWhiteSpace($Text)) {
                throw '查詢文字不可為空。'
            }
            $arguments = @('query', $Text, '--limit', [string]$Limit)
            if ($Project) {
                $arguments += @('--project', $Project)
            }
            Invoke-HistoryRuntime -Arguments $arguments
        }
        'mode' {
            if ($Text -notin @('lexical', 'hybrid')) {
                throw 'mode 必須是 lexical 或 hybrid。'
            }
            Invoke-HistoryRuntime -Arguments @('mode', $Text)
        }
        'project' {
            switch ($Text) {
                'list' {
                    Invoke-HistoryRuntime -Arguments @('project', 'list')
                }
                'add' {
                    if ([string]::IsNullOrWhiteSpace($Value)) {
                        throw '用法：project-history.ps1 project add <path>'
                    }
                    $projectPath = [IO.Path]::GetFullPath($Value)
                    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
                        throw "專案不存在：$projectPath"
                    }
                    $auxiliary = if ($IncludeAuxiliary) {
                        '包含 Git 與核准文件'
                    } else {
                        '只含正式 docs/history Records'
                    }
                    Confirm-Mutation `
                        -Description "Allowlist add：$projectPath（$auxiliary）"
                    $arguments = @('project', 'add', $projectPath, '--yes')
                    if ($IncludeAuxiliary) {
                        $arguments += '--include-auxiliary'
                    }
                    Invoke-HistoryRuntime -Arguments $arguments
                }
                'remove' {
                    if ([string]::IsNullOrWhiteSpace($Value)) {
                        throw '用法：project-history.ps1 project remove <name>'
                    }
                    Confirm-Mutation -Description "Allowlist remove：$Value"
                    Invoke-HistoryRuntime -Arguments @(
                        'project', 'remove', $Value, '--yes'
                    )
                }
                default {
                    throw 'project action 必須是 list、add 或 remove。'
                }
            }
        }
        'candidate' {
            switch ($Text) {
                'list' {
                    Invoke-HistoryRuntime -Arguments @('candidate', 'list')
                }
                'scan' {
                    if ([string]::IsNullOrWhiteSpace($Value)) {
                        throw '用法：project-history.ps1 candidate scan <project>'
                    }
                    Invoke-HistoryRuntime -Arguments @(
                        'candidate', 'scan', $Value, '--limit', [string]$Limit
                    )
                }
                'defer' {
                    if ([string]::IsNullOrWhiteSpace($Value)) {
                        throw '用法：project-history.ps1 candidate defer <id>'
                    }
                    Invoke-HistoryRuntime -Arguments @(
                        'candidate', 'defer', $Value
                    )
                }
                'exclude' {
                    if ([string]::IsNullOrWhiteSpace($Value)) {
                        throw '用法：project-history.ps1 candidate exclude <id>'
                    }
                    Confirm-Mutation -Description "Candidate exclude：$Value"
                    Invoke-HistoryRuntime -Arguments @(
                        'candidate', 'exclude', $Value, '--yes'
                    )
                }
                'retain' {
                    if (
                        [string]::IsNullOrWhiteSpace($Value) -or
                        [string]::IsNullOrWhiteSpace($RecordPath)
                    ) {
                        throw (
                            '用法：project-history.ps1 candidate retain <id> ' +
                            '-RecordPath <confirmed-record.md>'
                        )
                    }
                    $resolvedRecord = [IO.Path]::GetFullPath($RecordPath)
                    if (-not (Test-Path -LiteralPath $resolvedRecord -PathType Leaf)) {
                        throw "Record draft 不存在：$resolvedRecord"
                    }
                    Confirm-Mutation -Description "Candidate retain：$Value"
                    Invoke-HistoryRuntime -Arguments @(
                        'candidate', 'retain', $Value,
                        '--record', $resolvedRecord, '--yes'
                    )
                }
                default {
                    throw (
                        'candidate action 必須是 list、scan、defer、exclude 或 retain。'
                    )
                }
            }
        }
    }
} catch {
    Write-Error $_
    exit 1
}
