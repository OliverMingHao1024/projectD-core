# ==============================================================================
# projectD-core -> Claude Code CLI 全域接線腳本
# ------------------------------------------------------------------------------
# 作用：把 projectD-core 的 core/agents、packs 接進 ~/.claude/。
# 特性：
#   - 冪等：重複執行安全，不會重複寫入
#   - 自動定位：不寫死路徑，複製/clone 到任何機器任何位置都能跑
#   - 不覆蓋 ~/.claude/CLAUDE.md 既有內容（例如 CODEGRAPH 區塊），只管理自己的
#     PROJECTD_CORE_START/END 標記區塊
#
# 用法：
#   pwsh -File scripts\setup.ps1
#   （或雙擊 scripts\setup.bat）
# ==============================================================================

$ErrorActionPreference = 'Stop'

function Resolve-ProjectDCore {
    if ($env:PROJECTD_CORE -and (Test-Path (Join-Path $env:PROJECTD_CORE 'core\constitution\rules.md'))) {
        return (Resolve-Path $env:PROJECTD_CORE).Path
    }
    $fromScript = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Test-Path (Join-Path $fromScript 'core\constitution\rules.md')) {
        return $fromScript
    }
    throw 'Cannot resolve projectD-core root (no core/constitution/rules.md found).'
}

$Core = Resolve-ProjectDCore
$ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$ClaudeAgents = Join-Path $ClaudeHome 'agents'
$ClaudeSkills = Join-Path $ClaudeHome 'skills'
$ClaudeClaudeMd = Join-Path $ClaudeHome 'CLAUDE.md'

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host " projectD-core -> Claude Code CLI 部署中..." -ForegroundColor Cyan
Write-Host " Core: $Core" -ForegroundColor Gray
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($dir in @($ClaudeHome, $ClaudeAgents, $ClaudeSkills)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

# --- Step 1｜設定 PROJECTD_CORE 環境變數 ---
Write-Host "[1/4] 設定 PROJECTD_CORE 環境變數..." -ForegroundColor White
[Environment]::SetEnvironmentVariable('PROJECTD_CORE', $Core, 'User')
Write-Host "    OK PROJECTD_CORE = $Core" -ForegroundColor Green

# --- Step 2｜複製角色 Agent（單一 .md 檔，Windows junction 不支援單檔）---
Write-Host "[2/4] 複製 PM/SA/SD/PG agent 到 ~/.claude/agents..." -ForegroundColor White
$agentFiles = Get-ChildItem -Path (Join-Path $Core 'core\agents') -Filter '*.md'
foreach ($f in $agentFiles) {
    Copy-Item $f.FullName (Join-Path $ClaudeAgents $f.Name) -Force
    Write-Host "    OK $($f.Name)" -ForegroundColor Green
}
Write-Host "    （修改 core/agents/ 內容後，重跑本腳本才會反映到全域）" -ForegroundColor DarkGray

# --- Step 3｜Junction 連結 packs 到 ~/.claude/skills ---
Write-Host "[3/4] 連結 packs 到 ~/.claude/skills（junction，即時反映）..." -ForegroundColor White
$packDirs = Get-ChildItem -Path (Join-Path $Core 'packs') -Directory
foreach ($dir in $packDirs) {
    $linkPath = Join-Path $ClaudeSkills $dir.Name
    if (Test-Path $linkPath) {
        $item = Get-Item $linkPath -Force
        if ($item.LinkType -eq 'Junction' -and $item.Target -contains $dir.FullName) {
            Write-Host "    OK $($dir.Name)（連結已存在）" -ForegroundColor DarkGray
            continue
        } else {
            Write-Host "    [!] $($dir.Name) 已存在非本專案連結，略過（請手動檢查）" -ForegroundColor Yellow
            continue
        }
    }
    New-Item -ItemType Junction -Path $linkPath -Target $dir.FullName | Out-Null
    Write-Host "    OK $($dir.Name) -> $($dir.FullName)" -ForegroundColor Green
}

# --- Step 4｜寫入 ~/.claude/CLAUDE.md 的 PROJECTD_CORE 區塊 ---
Write-Host "[4/4] 寫入 ~/.claude/CLAUDE.md 的 session 啟動協議區塊..." -ForegroundColor White
$blockStart = '<!-- PROJECTD_CORE_START -->'
$blockEnd = '<!-- PROJECTD_CORE_END -->'
$bt = '`'
$rulesPath = Join-Path $Core 'core\constitution\rules.md'
$vaultPath = Join-Path $Core 'vault\README.md'
$block = @"
$blockStart
## projectD-core

個人擁有的 AI 治理核心（$bt$Core$bt）。每次 session 開始時：

1. 讀 $bt$rulesPath$bt（L0 規則）
2. 讀 $bt$vaultPath$bt，依其 init 序列讀取 identity/memory/governance
3. 依 governance INDEX 的 L1-L6 摘要做語意路由，只載入命中的治理規則
4. 需要技術棧規範時，才讀對應的 pack（已連結於 $bt~/.claude/skills/$bt：
   csharp、frontend-react-angular、python）

角色 agent（已複製於 $bt~/.claude/agents/$bt）：${bt}pm$bt（需求釐清）、${bt}sa$bt（技術分析）、
${bt}sd$bt（架構設計）、${bt}pg$bt（實作/審查/測試）。角色按任務需要選用，
低風險小任務不必跑完整流水線。
$blockEnd
"@

if (Test-Path $ClaudeClaudeMd) {
    $content = Get-Content $ClaudeClaudeMd -Raw
} else {
    $content = ''
}

if ($content -match [regex]::Escape($blockStart)) {
    $pattern = [regex]::Escape($blockStart) + '[\s\S]*?' + [regex]::Escape($blockEnd)
    $content = [regex]::Replace($content, $pattern, $block.Trim())
    Write-Host "    OK 已更新既有區塊" -ForegroundColor Green
} else {
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { $content += "`n" }
    $content += "`n" + $block.Trim() + "`n"
    Write-Host "    OK 已附加新區塊" -ForegroundColor Green
}
Set-Content -Path $ClaudeClaudeMd -Value $content -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host " 部署完成" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "移機到新裝置：複製/clone 整個 projectD-core 到任意路徑，重跑本腳本即可。" -ForegroundColor Gray
Write-Host "回滾：pwsh -File scripts\uninstall.ps1" -ForegroundColor DarkGray
Write-Host ""
