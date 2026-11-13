# Part of ProjectD.GovernanceWiring.psm1; dot-sourced into that module.
# Global and Fleet desired state (what should be installed).

function Get-CanonicalSkillDirectories {
    param([Parameter(Mandatory)][string]$Core)

    $coreSkills = @(
        Get-ChildItem -LiteralPath (Join-Path $Core 'core\skills') -Directory |
            Where-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')
            }
    )
    $packSkills = @(
        Get-ChildItem -LiteralPath (Join-Path $Core 'packs') -Directory |
            Where-Object {
                $_.Name -notlike '_*' -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md'))
            }
    )
    $skills = @($coreSkills) + @($packSkills)
    $duplicates = @(
        $skills |
            Group-Object Name |
            Where-Object Count -GT 1 |
            Select-Object -ExpandProperty Name
    )
    if ($duplicates.Count -gt 0) {
        throw "Duplicate canonical skill names: $($duplicates -join ', ')"
    }
    return $skills
}

function New-GlobalGovernanceWiring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Core,
        [string]$ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
        [string]$CodexHome = $(if ($env:CODEX_HOME) {
            [IO.Path]::GetFullPath($env:CODEX_HOME)
        } else {
            Join-Path $env:USERPROFILE '.codex'
        }),
        [string]$SharedAgentSkills = (
            Join-Path (Join-Path $env:USERPROFILE '.agents') 'skills'
        ),
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$EnvironmentScope = 'User',
        [string]$StatePath = (Join-Path $Core '.local\governance-wiring-state.json')
    )

    $resolvedCore = [IO.Path]::GetFullPath($Core)
    $resources = [Collections.Generic.List[object]]::new()
    $owner = 'projectD-core/global'
    $claudeAgents = Join-Path $ClaudeHome 'agents'
    $claudeCommands = Join-Path $ClaudeHome 'commands'
    $claudeSkills = Join-Path $ClaudeHome 'skills'

    foreach ($source in @(
        Get-ChildItem -LiteralPath (Join-Path $resolvedCore 'core\agents') `
            -Filter '*.md' -File
    )) {
        $resources.Add((New-FileCopyResource `
            -Path (Join-Path $claudeAgents $source.Name) `
            -Source $source.FullName `
            -Owner $owner))
    }
    $commandDirectory = Join-Path $resolvedCore 'core\commands'
    if (Test-Path -LiteralPath $commandDirectory -PathType Container) {
        foreach ($source in @(
            Get-ChildItem -LiteralPath $commandDirectory -Filter '*.md' -File
        )) {
            $resources.Add((New-FileCopyResource `
                -Path (Join-Path $claudeCommands $source.Name) `
                -Source $source.FullName `
                -Owner $owner))
        }
    }

    $coreSkillRoot = [IO.Path]::GetFullPath(
        (Join-Path $resolvedCore 'core\skills')
    )
    foreach ($skill in @(Get-CanonicalSkillDirectories $resolvedCore)) {
        $desiredState = if (
            [IO.Path]::GetFullPath($skill.Parent.FullName) -ceq $coreSkillRoot
        ) { 'Present' } else { 'Absent' }
        $resources.Add((New-JunctionResource `
            -Path (Join-Path $claudeSkills $skill.Name) `
            -Target $skill.FullName `
            -Owner $owner `
            -DesiredState $desiredState))
        $resources.Add((New-JunctionResource `
            -Path (Join-Path $SharedAgentSkills $skill.Name) `
            -Target $skill.FullName `
            -Owner $owner `
            -DesiredState $desiredState))
    }
    # Claude Code mods (core/mods/<name> with .claude-plugin/plugin.json) are linked
    # into ~/.claude/mods/<name>; settings.json env CLAUDE_CODE_PLUGIN_DIRS names them.
    $modRoot = Join-Path $resolvedCore 'core\mods'
    if (Test-Path -LiteralPath $modRoot -PathType Container) {
        foreach ($mod in @(
            Get-ChildItem -LiteralPath $modRoot -Directory |
                Where-Object {
                    Test-Path -LiteralPath (
                        Join-Path $_.FullName '.claude-plugin\plugin.json'
                    )
                }
        )) {
            $resources.Add((New-JunctionResource `
                -Path (Join-Path (Join-Path $ClaudeHome 'mods') $mod.Name) `
                -Target $mod.FullName `
                -Owner $owner))
        }
    }
    foreach ($retiredSkill in @('grill-me')) {
        $retiredTarget = Join-Path $resolvedCore "core\skills\$retiredSkill"
        foreach ($skillRoot in @($claudeSkills, $SharedAgentSkills)) {
            $resources.Add((New-JunctionResource `
                -Path (Join-Path $skillRoot $retiredSkill) `
                -Target $retiredTarget `
                -Owner $owner `
                -DesiredState Absent))
        }
    }

    $blockStart = '<!-- PROJECTD_CORE_START -->'
    $blockEnd = '<!-- PROJECTD_CORE_END -->'
    $bt = '`'
    $rulesPath = Join-Path $resolvedCore 'core\constitution\rules.md'
    $vaultPath = Join-Path $resolvedCore 'vault\README.md'
    $governancePath = Join-Path $resolvedCore 'vault\governance\INDEX.md'
    $rolesPath = Join-Path $resolvedCore 'core\agents'
    $claudeBlock = @"
$blockStart
## projectD-core

個人擁有的 AI 治理核心（$bt$resolvedCore$bt）。每次 session 開始時：

1. 讀 $bt$rulesPath$bt（L0 規則）
2. 讀 $bt$vaultPath$bt，依其 init 序列讀取 identity/memory/governance
3. 依 governance INDEX 的 L1-L6 摘要做語意路由，只載入命中的治理規則
4. 通用 workflow Skill 由 $bt~/.claude/skills/$bt 按需載入；技術棧 pack 由 Fleet
   接到各專案的 ${bt}.claude/skills/$bt，不放進全域 Skill catalog

角色 agent（已複製於 $bt~/.claude/agents/$bt）：${bt}pm$bt（需求釐清）、${bt}sa$bt（技術分析）、
${bt}ux$bt（互動設計）、${bt}sd$bt（架構設計）、${bt}pg$bt（實作/審查/測試）、${bt}qa$bt（獨立驗證）。
角色按任務需要選用，低風險小任務不必跑完整流水線。
$blockEnd
"@
    $codexBlock = @"
$blockStart
## projectD-core

本機共用 AI 治理核心位於 $bt$resolvedCore$bt。每次 Codex session 開始時：

1. 讀 $bt$rulesPath$bt（L0 規則）
2. 讀 $bt$vaultPath$bt，依其 init 序列讀取 identity、memory、governance
3. 依 $bt$governancePath$bt 的 L1-L6 摘要做語意路由，只載入命中的治理規則
4. 通用 workflow Skill 由 $bt$SharedAgentSkills$bt 按需載入；技術棧 pack 由 Fleet
   接到各專案的 ${bt}.agents/skills/$bt，不放進全域 Skill catalog
5. 只有任務需要角色分工時，才讀 $bt$rolesPath$bt 下對應的 pm、sa、ux、sd、pg、qa 指引

專案自身較近的 AGENTS.md 與使用者當次明確指令優先；不要預先載入整個 core。
$blockEnd
"@
    $resources.Add((New-ManagedBlockResource `
        -Path (Join-Path $ClaudeHome 'CLAUDE.md') `
        -BlockStart $blockStart `
        -BlockEnd $blockEnd `
        -Content $claudeBlock `
        -Owner $owner))
    $resources.Add((New-ManagedBlockResource `
        -Path (Join-Path $CodexHome 'AGENTS.md') `
        -BlockStart $blockStart `
        -BlockEnd $blockEnd `
        -Content $codexBlock `
        -Owner $owner))
    $resources.Add((New-EnvironmentResource `
        -Name 'PROJECTD_CORE' `
        -Value $resolvedCore `
        -Scope $EnvironmentScope `
        -Owner $owner))

    return [pscustomobject]@{
        Resources = $resources.ToArray()
        StatePath = [IO.Path]::GetFullPath($StatePath)
    }
}

function New-FleetGovernanceBlock {
    param([Parameter(Mandatory)][object]$FleetItem)

    $packs = @(
        $FleetItem.packs |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            }
    )
    $packText = if ($packs.Count -gt 0) {
        ($packs | ForEach-Object { "``$([string]$_)``" }) -join '、'
    } else {
        '無指定 pack'
    }
    return @(
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
    ) -join "`n"
}

function New-FleetGovernanceWiring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Core,
        [Parameter(Mandatory)][object[]]$FleetItems,
        [string]$StatePath = (
            Join-Path $Core '.local\fleet-governance-wiring-state.json'
        )
    )

    $resolvedCore = [IO.Path]::GetFullPath($Core)
    $resources = [Collections.Generic.List[object]]::new()
    foreach ($item in $FleetItems) {
        $projectPath = [string]$item.path
        if ([string]::IsNullOrWhiteSpace($projectPath)) {
            throw '[fleet] project path is empty.'
        }
        if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
            throw "[$projectPath] project directory is missing."
        }
        if ([string]$item.category -notin @('work', 'side')) {
            throw "[$projectPath] category must be work or side."
        }
        $selectedPacks = @(
            $item.packs |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_)
                } |
                ForEach-Object { [string]$_ } |
                Sort-Object -Unique
        )
        $invalidPacks = @(
            $selectedPacks |
                Where-Object { $_ -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' }
        )
        if ($invalidPacks.Count -gt 0) {
            throw "[$projectPath] invalid pack names: $($invalidPacks -join ', ')."
        }
        $missingPacks = @(
            $selectedPacks |
                Where-Object {
                    -not (Test-Path -LiteralPath (
                        Join-Path $resolvedCore "packs\$([string]$_)\SKILL.md"
                    ))
                }
        )
        if ($missingPacks.Count -gt 0) {
            throw "[$projectPath] missing packs: $($missingPacks -join ', ')."
        }
        $content = New-FleetGovernanceBlock $item
        foreach ($entryName in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')) {
            $resources.Add((New-ManagedBlockResource `
                -Path (Join-Path $projectPath $entryName) `
                -BlockStart '<!-- PROJECTD_CORE_START -->' `
                -BlockEnd '<!-- PROJECTD_CORE_END -->' `
                -Content $content `
                -Owner "projectD-core/fleet/$projectPath"))
        }
        foreach ($pack in $selectedPacks) {
            $target = Join-Path $resolvedCore "packs\$pack"
            foreach ($relativeRoot in @('.agents\skills', '.claude\skills')) {
                $resources.Add((New-JunctionResource `
                    -Path (Join-Path $projectPath "$relativeRoot\$pack") `
                    -Target $target `
                    -Owner "projectD-core/fleet/$projectPath"))
            }
        }
        $gitIgnoreStart = '# PROJECTD_CORE_AI_AGENT_MD_START'
        $gitIgnoreEnd = '# PROJECTD_CORE_AI_AGENT_MD_END'
        $gitIgnoreLines = [Collections.Generic.List[string]]::new()
        foreach ($line in @(
            $gitIgnoreStart,
            '# AI agent entry files managed by projectD-core.',
            '/AGENTS.md',
            '/CLAUDE.md',
            '/GEMINI.md'
        )) {
            $gitIgnoreLines.Add($line)
        }
        foreach ($pack in $selectedPacks) {
            $gitIgnoreLines.Add("/.agents/skills/$pack")
            $gitIgnoreLines.Add("/.claude/skills/$pack")
        }
        $gitIgnoreLines.Add($gitIgnoreEnd)
        $gitIgnoreContent = $gitIgnoreLines -join "`n"
        $resources.Add((New-ManagedBlockResource `
            -Path (Join-Path $projectPath '.gitignore') `
            -BlockStart $gitIgnoreStart `
            -BlockEnd $gitIgnoreEnd `
            -Content $gitIgnoreContent `
            -Owner "projectD-core/fleet/$projectPath"))
    }
    return [pscustomobject]@{
        Resources = $resources.ToArray()
        StatePath = [IO.Path]::GetFullPath($StatePath)
    }
}
