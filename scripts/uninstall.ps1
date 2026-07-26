# ==============================================================================
# projectD-core -> Claude Code + Codex + GitHub Copilot 移除腳本（setup.ps1 的反向操作）
# ==============================================================================

$ErrorActionPreference = 'Stop'

function Resolve-ProjectDCore {
    $fromScript = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Test-Path (Join-Path $fromScript 'core\constitution\rules.md')) {
        return $fromScript
    }
    throw 'Cannot resolve projectD-core root (no core/constitution/rules.md found).'
}

function Remove-ManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Owner
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "    OK [$Owner] 入口檔不存在，跳過" -ForegroundColor DarkGray
        return
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = [regex]::Escape('<!-- PROJECTD_CORE_START -->') +
        '[\s\S]*?' +
        [regex]::Escape('<!-- PROJECTD_CORE_END -->')
    if ($content -match $pattern) {
        $content = [regex]::Replace($content, $pattern, '').TrimEnd() + "`n"
        Set-Content -LiteralPath $Path -Value $content -Encoding UTF8 -NoNewline
        Write-Host "    OK [$Owner] 已移除區塊" -ForegroundColor Green
    } else {
        Write-Host "    OK [$Owner] 沒有找到區塊，跳過" -ForegroundColor DarkGray
    }
}

function Remove-OwnedJunction {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Owner
    )

    $item = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }

    $expectedTarget = [IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
    $isExpected = $false
    foreach ($candidateTarget in @($item.Target)) {
        if ($candidateTarget -and [string]::Equals(
            [IO.Path]::GetFullPath($candidateTarget).TrimEnd('\'),
            $expectedTarget,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            $isExpected = $true
            break
        }
    }

    if ($item.LinkType -eq 'Junction' -and $isExpected) {
        Remove-Item -LiteralPath $LinkPath -Force
        Write-Host "    OK [$Owner] 已移除 $($item.Name)" -ForegroundColor Green
    } else {
        Write-Host "    [!] [$Owner] $LinkPath 不是本專案 junction，跳過" -ForegroundColor Yellow
    }
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
Write-Host "移除 projectD-core 的 Claude Code + Codex 全域接線..." -ForegroundColor Cyan
Write-Host ""

# --- 移除複製的 agent 檔案 ---
Write-Host "[1/7] 移除 ~/.claude/agents 下的 projectD-core agents..." -ForegroundColor White
$agentNames = Get-ChildItem -LiteralPath (Join-Path $Core 'core\agents') -Filter '*.md' |
    Select-Object -ExpandProperty Name
foreach ($name in $agentNames) {
    $p = Join-Path $ClaudeAgents $name
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force
        Write-Host "    OK 已移除 $name" -ForegroundColor Green
    }
}

# --- 移除複製的 slash command 檔案 ---
Write-Host "[2/7] 移除 ~/.claude/commands 下的 projectD-core commands..." -ForegroundColor White
$commandDir = Join-Path $Core 'core\commands'
if (Test-Path -LiteralPath $commandDir) {
    $commandNames = Get-ChildItem -LiteralPath $commandDir -Filter '*.md' |
        Select-Object -ExpandProperty Name
    foreach ($name in $commandNames) {
        $p = Join-Path $ClaudeCommands $name
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
            Write-Host "    OK 已移除 $name" -ForegroundColor Green
        }
    }
}

# --- 移除 Claude / Codex / Copilot skill junction ---
$coreSkillDirs = Get-ChildItem -LiteralPath (Join-Path $Core 'core\skills') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }
$packSkillDirs = Get-ChildItem -LiteralPath (Join-Path $Core 'packs') -Directory |
    Where-Object { $_.Name -notlike '_*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) }
$skillDirs = @($coreSkillDirs) + @($packSkillDirs)
Write-Host "[3/7] 移除 ~/.claude/skills 下的 projectD-core skill junction..." -ForegroundColor White
foreach ($dir in $skillDirs) {
    Remove-OwnedJunction `
        -LinkPath (Join-Path $ClaudeSkills $dir.Name) `
        -TargetPath $dir.FullName `
        -Owner 'Claude'
}

Write-Host "[4/7] 移除 ~/.agents/skills 下的 projectD-core skill junction..." -ForegroundColor White
foreach ($dir in $skillDirs) {
    Remove-OwnedJunction `
        -LinkPath (Join-Path $SharedAgentSkills $dir.Name) `
        -TargetPath $dir.FullName `
        -Owner 'Codex/Copilot'
}

# --- 移除 Claude / Codex 入口區塊 ---
Write-Host "[5/7] 移除 ~/.claude/CLAUDE.md 的 PROJECTD_CORE 區塊..." -ForegroundColor White
Remove-ManagedBlock -Path $ClaudeClaudeMd -Owner 'Claude'

Write-Host "[6/7] 移除 Codex 全域 AGENTS.md 的 PROJECTD_CORE 區塊..." -ForegroundColor White
Remove-ManagedBlock -Path $CodexAgentsMd -Owner 'Codex'

# --- 移除環境變數 ---
Write-Host "[7/7] 移除 PROJECTD_CORE 環境變數..." -ForegroundColor White
$configuredCore = [Environment]::GetEnvironmentVariable('PROJECTD_CORE', 'User')
if ($configuredCore -and [string]::Equals(
    [IO.Path]::GetFullPath($configuredCore).TrimEnd('\'),
    [IO.Path]::GetFullPath($Core).TrimEnd('\'),
    [StringComparison]::OrdinalIgnoreCase
)) {
    [Environment]::SetEnvironmentVariable('PROJECTD_CORE', $null, 'User')
    Write-Host "    OK 已移除" -ForegroundColor Green
} elseif ($configuredCore) {
    Write-Host "    [!] PROJECTD_CORE 已指向其他位置，保留不動：$configuredCore" -ForegroundColor Yellow
} else {
    Write-Host "    OK 環境變數不存在，跳過" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "移除完成。projectD-core repo 本身未被刪除。" -ForegroundColor Cyan
Write-Host ""
