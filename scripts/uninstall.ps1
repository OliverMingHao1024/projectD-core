# ==============================================================================
# projectD-core -> Claude Code CLI 移除腳本（setup.ps1 的反向操作）
# ==============================================================================

$ErrorActionPreference = 'Stop'

$ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$ClaudeAgents = Join-Path $ClaudeHome 'agents'
$ClaudeSkills = Join-Path $ClaudeHome 'skills'
$ClaudeClaudeMd = Join-Path $ClaudeHome 'CLAUDE.md'

Write-Host ""
Write-Host "移除 projectD-core 全域接線..." -ForegroundColor Cyan
Write-Host ""

# --- 移除複製的 agent 檔案 ---
Write-Host "[1/4] 移除 ~/.claude/agents 下的 pm/sa/sd/pg.md..." -ForegroundColor White
foreach ($name in @('pm.md', 'sa.md', 'sd.md', 'pg.md')) {
    $p = Join-Path $ClaudeAgents $name
    if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host "    OK 已移除 $name" -ForegroundColor Green
    }
}

# --- 移除 packs junction ---
Write-Host "[2/4] 移除 ~/.claude/skills 下的 pack junction..." -ForegroundColor White
foreach ($name in @('csharp', 'frontend-react-angular', 'python')) {
    $p = Join-Path $ClaudeSkills $name
    if (Test-Path $p) {
        $item = Get-Item $p -Force
        if ($item.LinkType -eq 'Junction') {
            Remove-Item $p -Force
            Write-Host "    OK 已移除 $name" -ForegroundColor Green
        } else {
            Write-Host "    [!] $name 不是 junction，跳過（可能是手動放的內容）" -ForegroundColor Yellow
        }
    }
}

# --- 移除 CLAUDE.md 區塊 ---
Write-Host "[3/4] 移除 ~/.claude/CLAUDE.md 的 PROJECTD_CORE 區塊..." -ForegroundColor White
if (Test-Path $ClaudeClaudeMd) {
    $content = Get-Content $ClaudeClaudeMd -Raw
    $pattern = [regex]::Escape('<!-- PROJECTD_CORE_START -->') + '[\s\S]*?' + [regex]::Escape('<!-- PROJECTD_CORE_END -->')
    if ($content -match $pattern) {
        $content = [regex]::Replace($content, $pattern, '').TrimEnd() + "`n"
        Set-Content -Path $ClaudeClaudeMd -Value $content -Encoding UTF8 -NoNewline
        Write-Host "    OK 已移除區塊" -ForegroundColor Green
    } else {
        Write-Host "    OK 沒有找到區塊，跳過" -ForegroundColor DarkGray
    }
}

# --- 移除環境變數 ---
Write-Host "[4/4] 移除 PROJECTD_CORE 環境變數..." -ForegroundColor White
[Environment]::SetEnvironmentVariable('PROJECTD_CORE', $null, 'User')
Write-Host "    OK 已移除" -ForegroundColor Green

Write-Host ""
Write-Host "移除完成。projectD-core repo 本身未被刪除。" -ForegroundColor Cyan
Write-Host ""
