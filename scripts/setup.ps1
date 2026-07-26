# ==============================================================================
# projectD-core -> Claude Code + Codex + GitHub Copilot 全域接線腳本
# ------------------------------------------------------------------------------
# 作用：
#   - Claude：把 agents、commands 與全部標準 skills 接進 ~/.claude/
#   - Codex：把啟動協議寫進 ~/.codex/AGENTS.md，skills 接進 ~/.agents/skills/
#   - GitHub Copilot：共用 ~/.agents/skills/，不維護另一份 skill 內容
# 特性：
#   - 冪等：重複執行安全，不會重複寫入
#   - 自動定位：不寫死路徑，複製/clone 到任何機器任何位置都能跑
#   - 不覆蓋既有 CLAUDE.md / AGENTS.md，只管理 PROJECTD_CORE_START/END 標記區塊
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

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Ensure-SkillJunction {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Owner
    )

    $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $expectedTarget = [IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
        $isExpected = $false
        foreach ($candidateTarget in @($existing.Target)) {
            if ($candidateTarget -and [string]::Equals(
                [IO.Path]::GetFullPath($candidateTarget).TrimEnd('\'),
                $expectedTarget,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                $isExpected = $true
                break
            }
        }

        if ($existing.LinkType -eq 'Junction' -and $isExpected) {
            Write-Host "    OK [$Owner] $($existing.Name)（連結已存在）" -ForegroundColor DarkGray
        } else {
            Write-Host "    [!] [$Owner] $LinkPath 已存在且非本專案 junction，略過" -ForegroundColor Yellow
        }
        return
    }

    New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
    Write-Host "    OK [$Owner] $(Split-Path $LinkPath -Leaf) -> $TargetPath" -ForegroundColor Green
}

function Set-ManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BlockStart,
        [Parameter(Mandatory)][string]$BlockEnd,
        [Parameter(Mandatory)][string]$Block,
        [Parameter(Mandatory)][string]$Owner
    )

    Ensure-Directory (Split-Path $Path -Parent)
    $content = if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Raw
    } else {
        ''
    }

    $pattern = [regex]::Escape($BlockStart) + '[\s\S]*?' + [regex]::Escape($BlockEnd)
    if ($content -match $pattern) {
        $content = [regex]::Replace($content, $pattern, $Block.Trim())
        Write-Host "    OK [$Owner] 已更新既有區塊" -ForegroundColor Green
    } elseif (
        $content -match [regex]::Escape($BlockStart) -or
        $content -match [regex]::Escape($BlockEnd)
    ) {
        throw "$Path 的 projectD-core 標記不完整，請先修復 START/END 標記。"
    } else {
        if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
            $content += "`n"
        }
        $content += "`n" + $Block.Trim() + "`n"
        Write-Host "    OK [$Owner] 已附加新區塊" -ForegroundColor Green
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8 -NoNewline
}

$Core = Resolve-ProjectDCore
$ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$ClaudeAgents = Join-Path $ClaudeHome 'agents'
$ClaudeSkills = Join-Path $ClaudeHome 'skills'
$ClaudeCommands = Join-Path $ClaudeHome 'commands'
$ClaudeClaudeMd = Join-Path $ClaudeHome 'CLAUDE.md'
$CodexHome = if ($env:CODEX_HOME) {
    [IO.Path]::GetFullPath($env:CODEX_HOME)
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$CodexAgentsMd = Join-Path $CodexHome 'AGENTS.md'
$SharedAgentSkills = Join-Path (Join-Path $env:USERPROFILE '.agents') 'skills'

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host " projectD-core -> Claude Code + Codex 部署中..." -ForegroundColor Cyan
Write-Host " Core: $Core" -ForegroundColor Gray
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($dir in @(
    $ClaudeHome,
    $ClaudeAgents,
    $ClaudeSkills,
    $ClaudeCommands,
    $CodexHome,
    $SharedAgentSkills
)) {
    Ensure-Directory $dir
}

# --- Step 1｜設定 PROJECTD_CORE 環境變數 ---
Write-Host "[1/6] 設定 PROJECTD_CORE 環境變數..." -ForegroundColor White
[Environment]::SetEnvironmentVariable('PROJECTD_CORE', $Core, 'User')
Write-Host "    OK PROJECTD_CORE = $Core" -ForegroundColor Green

# --- Step 2｜複製角色 Agent（單一 .md 檔，Windows junction 不支援單檔）---
Write-Host "[2/6] 複製 PM/SA/SD/PG agent 到 ~/.claude/agents..." -ForegroundColor White
$agentFiles = Get-ChildItem -Path (Join-Path $Core 'core\agents') -Filter '*.md'
foreach ($f in $agentFiles) {
    Copy-Item $f.FullName (Join-Path $ClaudeAgents $f.Name) -Force
    Write-Host "    OK $($f.Name)" -ForegroundColor Green
}
Write-Host "    （修改 core/agents/ 內容後，重跑本腳本才會反映到全域）" -ForegroundColor DarkGray

# --- Step 3｜複製 slash command（單一 .md 檔，Windows junction 不支援單檔）---
Write-Host "[3/6] 複製 slash command 到 ~/.claude/commands..." -ForegroundColor White
$cmdDir = Join-Path $Core 'core\commands'
if (Test-Path $cmdDir) {
    $cmdFiles = Get-ChildItem -Path $cmdDir -Filter '*.md'
    foreach ($f in $cmdFiles) {
        Copy-Item $f.FullName (Join-Path $ClaudeCommands $f.Name) -Force
        Write-Host "    OK $($f.Name)" -ForegroundColor Green
    }
    Write-Host "    （修改 core/commands/ 內容後，重跑本腳本才會反映到全域）" -ForegroundColor DarkGray
} else {
    Write-Host "    OK core/commands 不存在，跳過" -ForegroundColor DarkGray
}

# --- Step 4｜把 canonical skills 連結到各工具的 discovery 目錄 ---
Write-Host "[4/6] 連結 core skills + packs 到 Claude / Codex / Copilot..." -ForegroundColor White
$coreSkillDirs = Get-ChildItem -Path (Join-Path $Core 'core\skills') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }
$packSkillDirs = Get-ChildItem -Path (Join-Path $Core 'packs') -Directory |
    Where-Object { $_.Name -notlike '_*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) }
$skillDirs = @($coreSkillDirs) + @($packSkillDirs)
$duplicateSkillNames = $skillDirs | Group-Object Name | Where-Object { $_.Count -gt 1 }
if ($duplicateSkillNames) {
    $names = ($duplicateSkillNames.Name | Sort-Object) -join ', '
    throw "Duplicate canonical skill names: $names"
}
foreach ($dir in $skillDirs) {
    Ensure-SkillJunction `
        -LinkPath (Join-Path $ClaudeSkills $dir.Name) `
        -TargetPath $dir.FullName `
        -Owner 'Claude'
    Ensure-SkillJunction `
        -LinkPath (Join-Path $SharedAgentSkills $dir.Name) `
        -TargetPath $dir.FullName `
        -Owner 'Codex/Copilot'
}

# --- Step 5｜寫入 ~/.claude/CLAUDE.md 的 PROJECTD_CORE 區塊 ---
Write-Host "[5/6] 寫入 ~/.claude/CLAUDE.md 的 session 啟動協議區塊..." -ForegroundColor White
$blockStart = '<!-- PROJECTD_CORE_START -->'
$blockEnd = '<!-- PROJECTD_CORE_END -->'
$bt = '`'
$rulesPath = Join-Path $Core 'core\constitution\rules.md'
$vaultPath = Join-Path $Core 'vault\README.md'
$governancePath = Join-Path $Core 'vault\governance\INDEX.md'
$rolesPath = Join-Path $Core 'core\agents'
$block = @"
$blockStart
## projectD-core

個人擁有的 AI 治理核心（$bt$Core$bt）。每次 session 開始時：

1. 讀 $bt$rulesPath$bt（L0 規則）
2. 讀 $bt$vaultPath$bt，依其 init 序列讀取 identity/memory/governance
3. 依 governance INDEX 的 L1-L6 摘要做語意路由，只載入命中的治理規則
4. 需要工作流或技術棧規範時，才使用已連結於 $bt~/.claude/skills/$bt 的對應 skill；
   canonical 內容只在 projectD-core 的 $btcore/skills/$bt 與 $btpacks/$bt 維護

角色 agent（已複製於 $bt~/.claude/agents/$bt）：${bt}pm$bt（需求釐清）、${bt}sa$bt（技術分析）、
${bt}sd$bt（架構設計）、${bt}pg$bt（實作/審查/測試）。角色按任務需要選用，
低風險小任務不必跑完整流水線。
$blockEnd
"@

Set-ManagedBlock `
    -Path $ClaudeClaudeMd `
    -BlockStart $blockStart `
    -BlockEnd $blockEnd `
    -Block $block `
    -Owner 'Claude'

# --- Step 6｜寫入 Codex 全域 AGENTS.md 的 PROJECTD_CORE 區塊 ---
Write-Host "[6/6] 寫入 Codex 全域 AGENTS.md 的 session 啟動協議區塊..." -ForegroundColor White
$codexBlock = @"
$blockStart
## projectD-core

本機共用 AI 治理核心位於 $bt$Core$bt。每次 Codex session 開始時：

1. 讀 $bt$rulesPath$bt（L0 規則）
2. 讀 $bt$vaultPath$bt，依其 init 序列讀取 identity、memory、governance
3. 依 $bt$governancePath$bt 的 L1-L6 摘要做語意路由，只載入命中的治理規則
4. 需要工作流或技術棧規範時，才使用已連結於 $bt$SharedAgentSkills$bt 的對應 skill；
   canonical 內容只在 projectD-core 的 $btcore/skills/$bt 與 $btpacks/$bt 維護
5. 只有任務需要角色分工時，才讀 $bt$rolesPath$bt 下對應的 pm、sa、sd、pg 指引

專案自身較近的 AGENTS.md 與使用者當次明確指令優先；不要預先載入整個 core。
$blockEnd
"@

Set-ManagedBlock `
    -Path $CodexAgentsMd `
    -BlockStart $blockStart `
    -BlockEnd $blockEnd `
    -Block $codexBlock `
    -Owner 'Codex'

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host " 部署完成" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Claude 全域入口：$ClaudeClaudeMd" -ForegroundColor Gray
Write-Host "Codex  全域入口：$CodexAgentsMd" -ForegroundColor Gray
Write-Host "移機到新裝置：複製/clone 整個 projectD-core 到任意路徑，重跑本腳本即可。" -ForegroundColor Gray
Write-Host "回滾：pwsh -File scripts\uninstall.ps1" -ForegroundColor DarkGray
Write-Host ""
