[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Check')]
    [string]$Mode = 'Check',

    [string]$FleetPath
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectDCore {
    if ($env:PROJECTD_CORE) {
        $candidate = Join-Path $env:PROJECTD_CORE 'core\constitution\rules.md'
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $env:PROJECTD_CORE).Path
        }
    }

    $fromScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    if (Test-Path -LiteralPath (Join-Path $fromScript 'core\constitution\rules.md')) {
        return $fromScript
    }

    throw 'Cannot resolve projectD-core root.'
}

function Normalize-Text {
    param([string]$Value)

    return (($Value -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Get-NewLine {
    param([string]$Content)

    if ($Content.Contains("`r`n")) {
        return "`r`n"
    }
    return "`n"
}

function New-GovernanceBlock {
    param(
        [object]$FleetItem,
        [string]$NewLine
    )

    $packs = @($FleetItem.packs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $packText = if ($packs.Count -gt 0) {
        ($packs | ForEach-Object { "``$([string]$_)``" }) -join '、'
    } else {
        '無指定 pack'
    }

    $lines = @(
        '<!-- PROJECTD_CORE_START -->',
        '## projectD-core 治理接線',
        '',
        "本專案已納入 projectD-core Fleet（category: ``$([string]$FleetItem.category)``；packs: $packText）。",
        '每次新 session 在修改專案前，必須：',
        '',
        '1. 解析 core path：優先使用環境變數 `PROJECTD_CORE`；否則尋找本專案同層的',
        '   `projectD-core` 目錄。',
        '2. 讀取 `<core>/core/constitution/rules.md`，將其視為 L0；任何本地 agent、skill、',
        '   command 或專案慣例都不得覆寫 L0。',
        '3. 讀取 `<core>/vault/README.md`，依 init 序列載入 identity、memory 與',
        '   governance INDEX。',
        '4. 依 governance INDEX 做 L1–L6 語意路由，只載入命中的治理文件與上述指定 packs。',
        '5. 若 core、L0 或 vault 無法解析，必須明確回報「projectD-core 未載入」，',
        '   在恢復治理接線前不得修改專案檔案；禁止靜默跳過。',
        '',
        '本專案既有入口規則繼續有效；與 L0 衝突時依 L0 的衝突處理規則辦理。',
        '<!-- PROJECTD_CORE_END -->'
    )

    return $lines -join $NewLine
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Invoke-CompliancePass {
    param(
        [object[]]$FleetItems,
        [string]$CoreRoot,
        [bool]$ApplyChanges
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $entryFiles = @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')
    $blockRegex = [regex]::new(
        '<!-- PROJECTD_CORE_START -->.*?<!-- PROJECTD_CORE_END -->',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    foreach ($item in $FleetItems) {
        $projectPath = [string]$item.path
        if ([string]::IsNullOrWhiteSpace($projectPath)) {
            $issues.Add('[fleet] project path is empty.')
            continue
        }
        if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
            $issues.Add("[$projectPath] project directory is missing.")
            continue
        }

        if ([string]$item.category -notin @('work', 'side')) {
            $issues.Add("[$projectPath] category must be work or side.")
        }

        $missingPacks = @(
            $item.packs |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Where-Object {
                    -not (Test-Path -LiteralPath (Join-Path $CoreRoot "packs\$([string]$_)\SKILL.md"))
                }
        )
        if ($missingPacks.Count -gt 0) {
            $issues.Add("[$projectPath] missing packs: $($missingPacks -join ', ').")
            continue
        }

        foreach ($entryName in $entryFiles) {
            $entryPath = Join-Path $projectPath $entryName
            if (-not (Test-Path -LiteralPath $entryPath)) {
                if ($ApplyChanges) {
                    $block = New-GovernanceBlock -FleetItem $item -NewLine "`n"
                    Write-Utf8File -Path $entryPath -Content ($block + "`n")
                    $script:ChangedFiles++
                } else {
                    $issues.Add("[$projectPath] $entryName is missing.")
                }
                continue
            }

            $content = [System.IO.File]::ReadAllText($entryPath)
            $matches = $blockRegex.Matches($content)
            if ($matches.Count -gt 1) {
                $issues.Add("[$projectPath] $entryName contains duplicate managed blocks.")
                continue
            }

            $newLine = Get-NewLine -Content $content
            $expectedBlock = New-GovernanceBlock -FleetItem $item -NewLine $newLine

            if ($matches.Count -eq 0) {
                if ($ApplyChanges) {
                    $prefix = $content.TrimEnd([char[]]"`r`n")
                    $updated = if ([string]::IsNullOrEmpty($prefix)) {
                        $expectedBlock + $newLine
                    } else {
                        $prefix + $newLine + $newLine + $expectedBlock + $newLine
                    }
                    Write-Utf8File -Path $entryPath -Content $updated
                    $script:ChangedFiles++
                } else {
                    $issues.Add("[$projectPath] $entryName is not connected.")
                }
                continue
            }

            if ((Normalize-Text -Value $matches[0].Value) -ne
                (Normalize-Text -Value $expectedBlock)) {
                if ($ApplyChanges) {
                    $updated = $blockRegex.Replace($content, $expectedBlock, 1)
                    Write-Utf8File -Path $entryPath -Content $updated
                    $script:ChangedFiles++
                } else {
                    $issues.Add("[$projectPath] $entryName managed block has drifted.")
                }
            }
        }
    }

    return $issues
}

$coreRoot = Resolve-ProjectDCore
if ([string]::IsNullOrWhiteSpace($FleetPath)) {
    $FleetPath = Join-Path $coreRoot 'fleet\fleet.json'
}
if (-not (Test-Path -LiteralPath $FleetPath)) {
    throw "Fleet file not found: $FleetPath"
}

$fleetItems = @(Get-Content -LiteralPath $FleetPath -Raw | ConvertFrom-Json)
if ($fleetItems.Count -eq 0) {
    throw "Fleet file contains no projects: $FleetPath"
}

$script:ChangedFiles = 0
$apply = $Mode -eq 'Apply'
$issues = @(Invoke-CompliancePass -FleetItems $fleetItems -CoreRoot $coreRoot -ApplyChanges $apply)
if ($apply) {
    $issues = @(Invoke-CompliancePass -FleetItems $fleetItems -CoreRoot $coreRoot -ApplyChanges $false)
}

if ($issues.Count -gt 0) {
    $issues | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    throw "Fleet governance check failed with $($issues.Count) issue(s)."
}

$entryCount = $fleetItems.Count * 3
Write-Host "[PASS] Fleet governance: $($fleetItems.Count) project(s), $entryCount entry file(s), $script:ChangedFiles changed." -ForegroundColor Green
