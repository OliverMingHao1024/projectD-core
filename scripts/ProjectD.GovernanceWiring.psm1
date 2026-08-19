Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ProjectDCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptRoot)

    if ($env:PROJECTD_CORE) {
        $candidate = Join-Path $env:PROJECTD_CORE 'core\constitution\rules.md'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:PROJECTD_CORE).Path
        }
    }
    $fromScript = [IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
    if (Test-Path -LiteralPath (
        Join-Path $fromScript 'core\constitution\rules.md'
    ) -PathType Leaf) {
        return $fromScript
    }
    throw 'Cannot resolve projectD-core root.'
}

function New-ManagedBlockResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BlockStart,
        [Parameter(Mandatory)][string]$BlockEnd,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Owner
    )

    if (
        -not $Content.Contains($BlockStart) -or
        -not $Content.Contains($BlockEnd)
    ) {
        throw 'Managed block content must contain both ownership markers.'
    }
    [pscustomobject]@{
        ResourceType = 'ManagedBlock'
        Path = [IO.Path]::GetFullPath($Path)
        BlockStart = $BlockStart
        BlockEnd = $BlockEnd
        Content = $Content.Trim()
        Owner = $Owner
    }
}

function New-FileCopyResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Owner
    )

    [pscustomobject]@{
        ResourceType = 'FileCopy'
        Path = [IO.Path]::GetFullPath($Path)
        Source = [IO.Path]::GetFullPath($Source)
        Owner = $Owner
    }
}

function New-JunctionResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Owner
    )

    [pscustomobject]@{
        ResourceType = 'Junction'
        Path = [IO.Path]::GetFullPath($Path)
        Target = [IO.Path]::GetFullPath($Target)
        Owner = $Owner
    }
}

function New-EnvironmentResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'User',
        [Parameter(Mandatory)][string]$Owner
    )

    [pscustomobject]@{
        ResourceType = 'Environment'
        Name = $Name
        Value = $Value
        Scope = $Scope
        Owner = $Owner
    }
}

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

    foreach ($skill in @(Get-CanonicalSkillDirectories $resolvedCore)) {
        $resources.Add((New-JunctionResource `
            -Path (Join-Path $claudeSkills $skill.Name) `
            -Target $skill.FullName `
            -Owner $owner))
        $resources.Add((New-JunctionResource `
            -Path (Join-Path $SharedAgentSkills $skill.Name) `
            -Target $skill.FullName `
            -Owner $owner))
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
4. 需要工作流或技術棧規範時，才使用已連結於 $bt~/.claude/skills/$bt 的對應 skill；
   canonical 內容只在 projectD-core 的 ${bt}core/skills/$bt 與 ${bt}packs/$bt 維護

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
4. 需要工作流或技術棧規範時，才使用已連結於 $bt$SharedAgentSkills$bt 的對應 skill；
   canonical 內容只在 projectD-core 的 ${bt}core/skills/$bt 與 ${bt}packs/$bt 維護
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
        $missingPacks = @(
            $item.packs |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_)
                } |
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
        $gitIgnoreStart = '# PROJECTD_CORE_AI_AGENT_MD_START'
        $gitIgnoreEnd = '# PROJECTD_CORE_AI_AGENT_MD_END'
        $gitIgnoreContent = @(
            $gitIgnoreStart,
            '# AI agent entry files managed by projectD-core.',
            '/AGENTS.md',
            '/CLAUDE.md',
            '/GEMINI.md',
            $gitIgnoreEnd
        ) -join "`n"
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

function Get-ResourceKey {
    param([Parameter(Mandatory)][object]$Resource)

    $identity = if ($Resource.ResourceType -eq 'Environment') {
        "$($Resource.Scope)|$($Resource.Name)"
    } else {
        [string]$Resource.Path
    }
    return (
        "$($Resource.ResourceType)|$identity"
    ).ToLowerInvariant()
}

function Read-WiringState {
    param([Parameter(Mandatory)][string]$StatePath)

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return @{
            schema_version = 1
            resources = @{}
        }
    }
    $state = Get-Content -Raw -LiteralPath $StatePath |
        ConvertFrom-Json -AsHashtable
    if ($state.schema_version -ne 1) {
        throw "Unsupported GovernanceWiring state schema: $($state.schema_version)"
    }
    if (-not $state.ContainsKey('resources')) {
        $state.resources = @{}
    }
    return $state
}

function Write-WiringState {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][hashtable]$State
    )

    $parent = Split-Path $StatePath -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ".$(Split-Path $StatePath -Leaf).$PID.tmp"
    try {
        $json = $State | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText(
            $temporary,
            $json + "`n",
            [Text.UTF8Encoding]::new($false)
        )
        Move-Item -LiteralPath $temporary -Destination $StatePath -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-ContentHash {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Normalize-WiringText {
    param([AllowEmptyString()][string]$Value)

    return (($Value -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Get-NewLine {
    param([AllowEmptyString()][string]$Content)

    if ($Content.Contains("`r`n")) {
        return "`r`n"
    }
    return "`n"
}

function Get-ManagedBlockInspection {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    if (-not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) {
        return @{ State = 'Missing'; Message = 'Target file is missing.' }
    }
    $content = [IO.File]::ReadAllText($Resource.Path)
    $startCount = ([regex]::Matches(
        $content,
        [regex]::Escape($Resource.BlockStart)
    )).Count
    $endCount = ([regex]::Matches(
        $content,
        [regex]::Escape($Resource.BlockEnd)
    )).Count
    if ($startCount -eq 0 -and $endCount -eq 0) {
        return @{ State = 'Missing'; Message = 'Managed block is absent.' }
    }
    if ($startCount -ne 1 -or $endCount -ne 1) {
        return @{
            State = 'Conflict'
            Message = 'Managed block markers are incomplete or duplicated.'
        }
    }
    $pattern = [regex]::new(
        [regex]::Escape($Resource.BlockStart) +
            '.*?' +
            [regex]::Escape($Resource.BlockEnd),
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $matches = $pattern.Matches($content)
    if ($matches.Count -ne 1) {
        return @{
            State = 'Conflict'
            Message = 'Managed block marker ordering is invalid.'
        }
    }
    if (
        (Normalize-WiringText $matches[0].Value) -eq
        (Normalize-WiringText $Resource.Content)
    ) {
        return @{ State = 'Compliant'; Message = 'Managed block matches.' }
    }
    return @{ State = 'Drift'; Message = 'Managed block content has drifted.' }
}

function Get-FileCopyInspection {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    if (-not (Test-Path -LiteralPath $Resource.Source -PathType Leaf)) {
        return @{ State = 'Conflict'; Message = 'Canonical source is missing.' }
    }
    if (-not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) {
        return @{ State = 'Missing'; Message = 'Copied file is missing.' }
    }
    $sourceHash = Get-ContentHash $Resource.Source
    $targetHash = Get-ContentHash $Resource.Path
    if ($sourceHash -eq $targetHash) {
        return @{ State = 'Compliant'; Message = 'Copied file matches source.' }
    }
    if (
        $StateEntry -and
        $StateEntry.ContainsKey('content_hash') -and
        $targetHash -eq [string]$StateEntry.content_hash
    ) {
        return @{ State = 'Drift'; Message = 'Owned copied file is outdated.' }
    }
    return @{
        State = 'Conflict'
        Message = 'Target content is not proven to be owned.'
    }
}

function Get-JunctionInspection {
    param([Parameter(Mandatory)][object]$Resource)

    $item = Get-Item -LiteralPath $Resource.Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return @{ State = 'Missing'; Message = 'Junction is missing.' }
    }
    $expected = [IO.Path]::GetFullPath($Resource.Target).TrimEnd('\')
    $matches = @(
        @($item.Target) | Where-Object {
            $_ -and [string]::Equals(
                [IO.Path]::GetFullPath([string]$_).TrimEnd('\'),
                $expected,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    if ($item.LinkType -eq 'Junction' -and $matches.Count -gt 0) {
        return @{ State = 'Compliant'; Message = 'Junction target matches.' }
    }
    return @{ State = 'Conflict'; Message = 'Path is not the owned junction.' }
}

function Get-EnvironmentInspection {
    param([Parameter(Mandatory)][object]$Resource)

    $current = [Environment]::GetEnvironmentVariable(
        $Resource.Name,
        $Resource.Scope
    )
    if ([string]::IsNullOrEmpty($current)) {
        return @{ State = 'Missing'; Message = 'Environment value is missing.' }
    }
    if ([string]::Equals(
        $current,
        $Resource.Value,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        return @{ State = 'Compliant'; Message = 'Environment value matches.' }
    }
    return @{
        State = 'Conflict'
        Message = 'Environment value is not owned by this wiring.'
    }
}

function Get-ResourceInspection {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    switch ($Resource.ResourceType) {
        'ManagedBlock' {
            return Get-ManagedBlockInspection $Resource $StateEntry
        }
        'FileCopy' {
            return Get-FileCopyInspection $Resource $StateEntry
        }
        'Junction' {
            return Get-JunctionInspection $Resource
        }
        'Environment' {
            return Get-EnvironmentInspection $Resource
        }
        default {
            throw "Unsupported GovernanceWiring resource: $($Resource.ResourceType)"
        }
    }
}

function Get-GovernanceWiringPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Resources,
        [ValidateSet('Apply', 'Remove', 'Check')]
        [string]$Action,
        [Parameter(Mandatory)][string]$StatePath
    )

    $state = Read-WiringState $StatePath
    $keys = @($Resources | ForEach-Object { Get-ResourceKey $_ })
    $duplicates = @(
        $keys | Group-Object | Where-Object Count -GT 1
    )
    if ($duplicates.Count -gt 0) {
        throw (
            'GovernanceWiring desired state contains duplicate resource keys: ' +
            (($duplicates | Select-Object -ExpandProperty Name) -join ', ')
        )
    }
    foreach ($resource in $Resources) {
        $key = Get-ResourceKey $resource
        $stateEntry = if ($state.resources.ContainsKey($key)) {
            $state.resources[$key]
        } else {
            $null
        }
        $inspection = Get-ResourceInspection $resource $stateEntry
        $operation = switch ($Action) {
            'Check' { 'None' }
            'Apply' {
                switch ($inspection.State) {
                    'Missing' { 'Create' }
                    'Drift' { 'Update' }
                    'Compliant' { 'None' }
                    default { 'Conflict' }
                }
            }
            'Remove' {
                switch ($inspection.State) {
                    'Missing' { 'None' }
                    'Compliant' { 'Remove' }
                    'Drift' { 'Remove' }
                    default { 'Conflict' }
                }
            }
        }
        [pscustomobject]@{
            Resource = $resource
            Key = $key
            State = $inspection.State
            Operation = $operation
            Message = $inspection.Message
        }
    }
}

function Get-ResourceSnapshot {
    param([Parameter(Mandatory)][object]$Resource)

    switch ($Resource.ResourceType) {
        { $_ -in @('ManagedBlock', 'FileCopy') } {
            $exists = Test-Path -LiteralPath $Resource.Path -PathType Leaf
            return @{
                ResourceType = $Resource.ResourceType
                Path = $Resource.Path
                Exists = $exists
                Bytes = if ($exists) {
                    [IO.File]::ReadAllBytes($Resource.Path)
                } else {
                    $null
                }
            }
        }
        'Junction' {
            $item = Get-Item -LiteralPath $Resource.Path -Force `
                -ErrorAction SilentlyContinue
            return @{
                ResourceType = 'Junction'
                Path = $Resource.Path
                Exists = $null -ne $item
                Target = if ($item) { @($item.Target)[0] } else { $null }
                LinkType = if ($item) { $item.LinkType } else { $null }
            }
        }
        'Environment' {
            return @{
                ResourceType = 'Environment'
                Name = $Resource.Name
                Scope = $Resource.Scope
                Value = [Environment]::GetEnvironmentVariable(
                    $Resource.Name,
                    $Resource.Scope
                )
            }
        }
    }
}

function Restore-ResourceSnapshot {
    param([Parameter(Mandatory)][hashtable]$Snapshot)

    switch ($Snapshot.ResourceType) {
        { $_ -in @('ManagedBlock', 'FileCopy') } {
            if ($Snapshot.Exists) {
                New-Item -ItemType Directory -Path (
                    Split-Path $Snapshot.Path -Parent
                ) -Force | Out-Null
                [IO.File]::WriteAllBytes($Snapshot.Path, $Snapshot.Bytes)
            } else {
                Remove-Item -LiteralPath $Snapshot.Path -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        'Junction' {
            Remove-Item -LiteralPath $Snapshot.Path -Force `
                -ErrorAction SilentlyContinue
            if ($Snapshot.Exists -and $Snapshot.LinkType -eq 'Junction') {
                New-Item -ItemType Directory -Path (
                    Split-Path $Snapshot.Path -Parent
                ) -Force | Out-Null
                New-Item -ItemType Junction -Path $Snapshot.Path `
                    -Target $Snapshot.Target | Out-Null
            }
        }
        'Environment' {
            [Environment]::SetEnvironmentVariable(
                $Snapshot.Name,
                $Snapshot.Value,
                $Snapshot.Scope
            )
        }
    }
}

function Set-ManagedBlockContent {
    param([Parameter(Mandatory)][object]$Resource)

    $parent = Split-Path $Resource.Path -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $content = if (Test-Path -LiteralPath $Resource.Path -PathType Leaf) {
        [IO.File]::ReadAllText($Resource.Path)
    } else {
        ''
    }
    $newLine = Get-NewLine $content
    $block = (Normalize-WiringText $Resource.Content) -replace "`n", $newLine
    $pattern = [regex]::new(
        [regex]::Escape($Resource.BlockStart) +
            '.*?' +
            [regex]::Escape($Resource.BlockEnd),
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($pattern.IsMatch($content)) {
        $updated = $pattern.Replace($content, $block, 1)
    } else {
        $prefix = $content.TrimEnd([char[]]"`r`n")
        $updated = if ([string]::IsNullOrEmpty($prefix)) {
            $block + $newLine
        } else {
            $prefix + $newLine + $newLine + $block + $newLine
        }
    }
    [IO.File]::WriteAllText(
        $Resource.Path,
        $updated,
        [Text.UTF8Encoding]::new($false)
    )
}

function Remove-ManagedBlockContent {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    if (-not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) {
        return
    }
    $content = [IO.File]::ReadAllText($Resource.Path)
    $newLine = Get-NewLine $content
    $pattern = [regex]::new(
        [regex]::Escape($Resource.BlockStart) +
            '.*?' +
            [regex]::Escape($Resource.BlockEnd),
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $updated = $pattern.Replace($content, '', 1).TrimEnd()
    if (
        [string]::IsNullOrWhiteSpace($updated) -and
        $StateEntry -and
        $StateEntry.created
    ) {
        Remove-Item -LiteralPath $Resource.Path -Force
        return
    }
    $final = if ($updated) { $updated + $newLine } else { '' }
    [IO.File]::WriteAllText(
        $Resource.Path,
        $final,
        [Text.UTF8Encoding]::new($false)
    )
}

function Invoke-ResourceMutation {
    param(
        [Parameter(Mandatory)][object]$PlanItem,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][hashtable]$State
    )

    $resource = $PlanItem.Resource
    $stateEntry = if ($State.resources.ContainsKey($PlanItem.Key)) {
        $State.resources[$PlanItem.Key]
    } else {
        $null
    }
    if ($PlanItem.Operation -eq 'None') {
        if ($Action -eq 'Remove') {
            $State.resources.Remove($PlanItem.Key)
            return
        }
        if (
            $Action -eq 'Apply' -and
            $resource.ResourceType -eq 'FileCopy' -and
            -not $stateEntry
        ) {
            $State.resources[$PlanItem.Key] = @{
                resource_type = 'FileCopy'
                content_hash = Get-ContentHash $resource.Path
            }
        }
        return
    }
    if ($Action -eq 'Apply') {
        switch ($resource.ResourceType) {
            'ManagedBlock' {
                $targetExisted = Test-Path `
                    -LiteralPath $resource.Path `
                    -PathType Leaf
                Set-ManagedBlockContent $resource
                $created = if (-not $targetExisted) {
                    $true
                } elseif ($stateEntry) {
                    [bool]$stateEntry.created
                } else {
                    $false
                }
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'ManagedBlock'
                    created = $created
                }
            }
            'FileCopy' {
                New-Item -ItemType Directory -Path (
                    Split-Path $resource.Path -Parent
                ) -Force | Out-Null
                Copy-Item -LiteralPath $resource.Source `
                    -Destination $resource.Path -Force
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'FileCopy'
                    content_hash = Get-ContentHash $resource.Path
                }
            }
            'Junction' {
                New-Item -ItemType Directory -Path (
                    Split-Path $resource.Path -Parent
                ) -Force | Out-Null
                New-Item -ItemType Junction -Path $resource.Path `
                    -Target $resource.Target | Out-Null
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'Junction'
                    target = $resource.Target
                }
            }
            'Environment' {
                [Environment]::SetEnvironmentVariable(
                    $resource.Name,
                    $resource.Value,
                    $resource.Scope
                )
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'Environment'
                    value = $resource.Value
                }
            }
        }
        return
    }

    switch ($resource.ResourceType) {
        'ManagedBlock' {
            Remove-ManagedBlockContent $resource $stateEntry
        }
        'FileCopy' {
            Remove-Item -LiteralPath $resource.Path -Force
        }
        'Junction' {
            Remove-Item -LiteralPath $resource.Path -Force
        }
        'Environment' {
            [Environment]::SetEnvironmentVariable(
                $resource.Name,
                $null,
                $resource.Scope
            )
        }
    }
    $State.resources.Remove($PlanItem.Key)
}

function Invoke-GovernanceWiring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Resources,
        [ValidateSet('Apply', 'Remove', 'Check')]
        [string]$Action,
        [Parameter(Mandatory)][string]$StatePath,
        [scriptblock]$AfterMutation
    )

    $plan = @(
        Get-GovernanceWiringPlan `
            -Resources $Resources `
            -Action $Action `
            -StatePath $StatePath
    )
    if ($Action -eq 'Check') {
        return $plan
    }
    $conflicts = @($plan | Where-Object Operation -EQ 'Conflict')
    if ($conflicts.Count -gt 0) {
        $details = ($conflicts | ForEach-Object {
            "$($_.Resource.ResourceType): $($_.Message)"
        }) -join '; '
        throw "GovernanceWiring preflight conflict: $details"
    }

    $state = Read-WiringState $StatePath
    $stateSnapshot = @{
        Exists = Test-Path -LiteralPath $StatePath -PathType Leaf
        Bytes = if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
            [IO.File]::ReadAllBytes($StatePath)
        } else {
            $null
        }
    }
    $mutations = @($plan | Where-Object Operation -NE 'None')
    $snapshots = @(
        $mutations | ForEach-Object {
            Get-ResourceSnapshot $_.Resource
        }
    )
    try {
        foreach ($item in $plan) {
            Invoke-ResourceMutation -PlanItem $item -Action $Action -State $state
            if ($item.Operation -ne 'None' -and $AfterMutation) {
                & $AfterMutation $item
            }
        }
        Write-WiringState -StatePath $StatePath -State $state
        $verification = @(
            Get-GovernanceWiringPlan `
                -Resources $Resources `
                -Action Check `
                -StatePath $StatePath
        )
        $expectedState = if ($Action -eq 'Apply') { 'Compliant' } else { 'Missing' }
        $failed = @($verification | Where-Object State -NE $expectedState)
        if ($failed.Count -gt 0) {
            $details = ($failed | ForEach-Object {
                "$($_.Resource.ResourceType)[$($_.Key)]: " +
                    "$($_.State) ($($_.Message))"
            }) -join '; '
            throw (
                "GovernanceWiring verification failed after ${Action}: " +
                $details
            )
        }
    } catch {
        for ($index = $snapshots.Count - 1; $index -ge 0; $index--) {
            Restore-ResourceSnapshot $snapshots[$index]
        }
        if ($stateSnapshot.Exists) {
            New-Item -ItemType Directory -Path (
                Split-Path $StatePath -Parent
            ) -Force | Out-Null
            [IO.File]::WriteAllBytes($StatePath, $stateSnapshot.Bytes)
        } else {
            Remove-Item -LiteralPath $StatePath -Force `
                -ErrorAction SilentlyContinue
        }
        throw
    }
    return $plan
}

Export-ModuleMember -Function @(
    'Resolve-ProjectDCore',
    'New-ManagedBlockResource',
    'New-FileCopyResource',
    'New-JunctionResource',
    'New-EnvironmentResource',
    'New-GlobalGovernanceWiring',
    'New-FleetGovernanceWiring',
    'Get-GovernanceWiringPlan',
    'Invoke-GovernanceWiring'
)
