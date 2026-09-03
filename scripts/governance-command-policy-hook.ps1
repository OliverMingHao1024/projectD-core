<#
Governance command policy hook (see docs/specs/governance-command-policy-hook.md).

This is deliberately a separate component from
scripts/governance-host-operation-hook.ps1 (the critical-tier, integrity-pinned
tamper-evident audit ledger). That ledger's source_sink_policy commits it to
never inspecting raw tool input; this hook's entire purpose is the opposite --
it reads Bash/PowerShell command text and MCP tool names to decide whether to
block a PreToolUse call. The two must never be merged.

Two independent fail-safe directions are used on purpose:
- Anonymous-tunnel and TFS-workflow-boundary detection fail OPEN (allow) on any
  internal error. A bug in this best-effort content-policy layer must never
  brick a session's ability to run shell commands -- that cost is worse than
  occasionally missing a violation.
- The DevSpace personal/work boundary fails CLOSED (deny) on any internal
  error, including a missing/unreadable classification registry or an unset
  PROJECTD_CORE. Mistakenly allowing DevSpace on a work project is a real
  security exposure (see docs/adr/0015-isolate-ai-agent-mcp-server-execution.md);
  mistakenly denying it just means registering the repo once.

The anonymous-tunnel rule has one conditional exception layered on top of its
fail-open default: devtunnel --allow-anonymous is allowed when the current
repo/machine is registered "personal" (reusing the DevSpace check above),
because containers/devspace-isolation/ now bounds what such a tunnel can
reach in that case -- see
docs/adr/0017-allow-anonymous-devtunnel-for-isolated-devspace-on-personal-registrations.md.
Any failure evaluating that exception falls back to "not exempted" (fail
closed for the exception itself), while the rule's own outer error handling
still fails open, unchanged.
#>

[CmdletBinding(DefaultParameterSetName = 'Hook')]
param(
    [Parameter(ParameterSetName = 'Hook')]
    [Parameter(ParameterSetName = 'Register')]
    [string]$ProjectRoot,

    [Parameter(ParameterSetName = 'Hook')]
    [Parameter(ParameterSetName = 'Register')]
    [string]$RegistryPath,

    [Parameter(ParameterSetName = 'Hook')]
    [ValidateSet('codex', 'claude')]
    [string]$HostName,

    [Parameter(ParameterSetName = 'Register')]
    [switch]$RegisterCurrentRepo,

    [Parameter(ParameterSetName = 'Register')]
    [switch]$RegisterCurrentMachine,

    [Parameter(ParameterSetName = 'Register', Mandatory)]
    [ValidateSet('personal', 'work')]
    [string]$Classification
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = if ($RegisterCurrentRepo) {
        (Get-Location).Path
    } else {
        Split-Path -Parent $PSScriptRoot
    }
}

function Read-BoundedStandardInput {
    param([long]$MaximumBytes = 2MB)
    $inputStream = [Console]::OpenStandardInput()
    $memory = [IO.MemoryStream]::new()
    $buffer = [byte[]]::new(8192)
    try {
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $MaximumBytes) {
                throw 'Hook input exceeds the allowed size.'
            }
            $memory.Write($buffer, 0, $read)
        }
        return [Text.Encoding]::UTF8.GetString($memory.ToArray())
    } finally {
        $memory.Dispose()
    }
}

function Stop-HookOperation {
    param([Parameter(Mandatory)][string]$Reason)

    if ($HostName -ceq 'codex') {
        $response = [pscustomobject][ordered]@{
            hookSpecificOutput = [pscustomobject][ordered]@{
                hookEventName = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = $Reason
            }
        }
        [Console]::Out.WriteLine(($response | ConvertTo-Json -Compress -Depth 4))
        exit 0
    }
    [Console]::Error.WriteLine($Reason)
    exit 2
}

function Get-NormalizedOriginHash {
    <#
    Hashes the repository's `origin` remote URL (not its local path, which
    differs per machine) so the same repository always resolves to the same
    key regardless of which machine it was cloned on. Embedded HTTPS
    credentials are stripped before hashing. SSH-form URLs (git@host:org/repo)
    are hashed as-is -- normalizing those is an explicit known limitation
    (see spec, Out of scope).
    #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    try {
        $url = & git -C $RepoRoot remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($url)) {
            return $null
        }
    } catch {
        return $null
    }
    $normalized = $url.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '^(https?://)[^@/]+@', '$1'
    $normalized = $normalized -replace '\.git/?$', ''
    $normalized = $normalized.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return 'sha256:' + [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-NormalizedMachineHash {
    <#
    Hashes the current computer name so a machine-level classification (e.g.
    "this whole laptop is my personal machine") never stores the raw hostname
    in a public repo -- hostnames often leak employer/device naming
    conventions, the same concern as repository remote URLs.
    #>
    $name = [Environment]::MachineName
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $normalized = $name.Trim().ToLowerInvariant()
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return 'sha256:' + [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-ProjectDCoreRoot {
    <#
    Resolves where the central project-classification registry lives.
    PROJECTD_CORE takes precedence (the documented cross-repo resolution
    convention, see core/skills/manage-requirement-knowledge). When unset,
    falls back to treating $FallbackRoot itself as projectD-core if it looks
    like it (has a vault/governance directory) -- this lets the hook resolve
    itself with zero extra configuration when deployed inside projectD-core,
    which is the only deployment that exists today.
    #>
    param([Parameter(Mandatory)][string]$FallbackRoot)
    if (
        $env:PROJECTD_CORE -and
        (Test-Path -LiteralPath $env:PROJECTD_CORE -PathType Container)
    ) {
        return (Resolve-Path -LiteralPath $env:PROJECTD_CORE).Path
    }
    $candidate = Join-Path $FallbackRoot 'vault\governance'
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        return $FallbackRoot
    }
    return $null
}

function Get-ClassificationRegistryPath {
    param(
        [Parameter(Mandatory)][string]$FallbackRoot,
        [string]$OverridePath
    )
    if ($OverridePath) { return $OverridePath }
    $coreRoot = Get-ProjectDCoreRoot -FallbackRoot $FallbackRoot
    if (-not $coreRoot) { return $null }
    return Join-Path $coreRoot 'vault\governance\project-classification.json'
}

function Test-DevSpaceToolAllowed {
    <#
    Returns $false (deny) for every uncertain condition: missing registry,
    unregistered repository/machine, malformed JSON, or any unexpected
    exception. Repository-level registration is checked first (more
    specific, wins); machine-level registration is the fallback for repos
    that were never individually registered. Only an explicit "personal"
    entry at whichever level matches returns $true.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$RegistryPathOverride
    )
    try {
        $registryPath = Get-ClassificationRegistryPath `
            -FallbackRoot $RepoRoot -OverridePath $RegistryPathOverride
        if (
            -not $registryPath -or
            -not (Test-Path -LiteralPath $registryPath -PathType Leaf)
        ) {
            return $false
        }
        $text = [Text.Encoding]::UTF8.GetString(
            [IO.File]::ReadAllBytes($registryPath)
        )
        $document = $text | ConvertFrom-Json

        $repoHash = Get-NormalizedOriginHash -RepoRoot $RepoRoot
        if (
            $repoHash -and
            $null -ne $document.repositories -and
            $document.repositories.PSObject.Properties.Name -contains $repoHash
        ) {
            return ([string]$document.repositories.$repoHash -ceq 'personal')
        }

        $machineHash = Get-NormalizedMachineHash
        if (
            $machineHash -and
            $null -ne $document.machines -and
            $document.machines.PSObject.Properties.Name -contains $machineHash
        ) {
            return ([string]$document.machines.$machineHash -ceq 'personal')
        }

        return $false
    } catch {
        return $false
    }
}

function Get-CommandText {
    param($ToolInput)
    if ($null -eq $ToolInput) { return $null }
    foreach ($key in @('command', 'script')) {
        if ($ToolInput.PSObject.Properties.Name -contains $key) {
            $value = $ToolInput.$key
            if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }
    return $null
}

function Get-TargetFilePath {
    <#
    Extracts a target file path from a structured file-editing tool's
    input (Edit's/Write's file_path, NotebookEdit's notebook_path). Returns
    $null for tools that don't shape their input this way.
    #>
    param($ToolInput)
    if ($null -eq $ToolInput) { return $null }
    foreach ($key in @('file_path', 'notebook_path', 'path')) {
        if ($ToolInput.PSObject.Properties.Name -contains $key) {
            $value = $ToolInput.$key
            if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }
    return $null
}

function Test-RegistryTamperViolation {
    <#
    Security review finding: project-classification.json had no integrity
    protection at all -- anything with filesystem write access could edit
    it directly to grant itself "personal" and bypass rule 3 and the
    anonymous-tunnel exception entirely, without ever going through
    Register-Classification's now-required interactive terminal. This
    closes the two most direct paths:
    - a structured file-editing tool (Edit/Write/NotebookEdit) targeting
      the resolved registry file path exactly;
    - a Bash/PowerShell command whose text names the registry file
      alongside a recognizable write/redirect indicator.
    This is NOT a complete defense (see docs/specs/governance-command-
    policy-hook.md addendum for what remains open): a sufficiently
    obfuscated write (a variable holding the filename, byte-by-byte
    writes, a wrapper script) can still evade text/parameter matching, the
    same limitation every rule in this file already has. Fails CLOSED
    (blocks) when uncertain, matching rule 3's severity, not rules 1/2's.
    #>
    param(
        [string]$ToolName,
        $ToolInput,
        [string]$CommandText,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$RegistryPathOverride
    )
    try {
        $registryPath = Get-ClassificationRegistryPath `
            -FallbackRoot $RepoRoot -OverridePath $RegistryPathOverride
        if (-not $registryPath) { return $false }
        $resolvedRegistry = [IO.Path]::GetFullPath($registryPath)

        if ($ToolName -match '(?i)^(edit|write|notebookedit)$') {
            $targetPath = Get-TargetFilePath -ToolInput $ToolInput
            if ($targetPath) {
                $resolvedTarget = [IO.Path]::GetFullPath($targetPath)
                if ($resolvedTarget.Equals(
                    $resolvedRegistry, [StringComparison]::OrdinalIgnoreCase
                )) {
                    return $true
                }
            }
            return $false
        }

        if (-not $CommandText) { return $false }
        $registryFileName = Split-Path -Leaf $resolvedRegistry
        $mentionsRegistry = $CommandText.Contains($registryFileName)
        $looksLikeWrite = [bool](
            $CommandText -match
                '(?i)(>>?|\bSet-Content\b|\bAdd-Content\b|\bOut-File\b|' +
                '\bcp\b|\bcopy\b|\bmv\b|\bmove\b|\bsed\s+-i\b|' +
                '\bConvertTo-Json\b.*\|)'
        )
        return ($mentionsRegistry -and $looksLikeWrite)
    } catch {
        return $true
    }
}

function Test-AnonymousTunnelViolation {
    <#
    Blocks devtunnel --allow-anonymous, EXCEPT when the current repo/machine
    is registered "personal" (the same check rule 3 uses). The exception
    exists because containers/devspace-isolation/ now bounds what an
    anonymous tunnel can actually reach when DevSpace only ever runs there on
    a personal-registered machine -- see the ADR recording this decision.
    This is NOT a blanket repeal: on a work-registered (or unregistered,
    fail-closed by Test-DevSpaceToolAllowed) repo/machine, anonymous tunnels
    are still always blocked, matching the original absolute rule.
    Unexpected errors in this function itself (not in the nested personal/
    work check, which already fails closed internally) still fail OPEN, same
    as before -- a bug here must not brick unrelated shell commands.
    #>
    param(
        [string]$CommandText,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$RegistryPathOverride
    )
    if (-not $CommandText) { return $false }
    try {
        <#
        Matches three distinct ways devtunnel actually grants anonymous
        access, confirmed against `devtunnel host --help` /
        `devtunnel access create --help`: the long flag, the short flag
        (`-a`), and `access create ... --anonymous` (no "allow-" prefix at
        all). A regex matching only "--allow-anonymous" verifiably missed
        all three of the actual commands this repo's own README instructs
        users to run.

        Checked per shell segment (split on ;, &&, ||, |, newlines), not
        against the whole command text at once -- matching "devtunnel"
        anywhere in the line and "-a" anywhere later in the line (even in
        an unrelated chained command, or inside an echoed string) produced
        a confirmed false positive; requiring both within the same segment
        keeps the -a/--anonymous short forms detectable without that.
        #>
        $looksAnonymous = $false
        foreach ($segment in ($CommandText -split '&&|\|\||[;|\n]')) {
            if (
                $segment -match '(?i)devtunnel(\.exe)?\b' -and
                $segment -match '(?i)(--allow-anonymous|--anonymous|(?<!\S)-a(?!\S))'
            ) {
                $looksAnonymous = $true
                break
            }
        }
        if (-not $looksAnonymous) { return $false }
        if (Test-DevSpaceToolAllowed -RepoRoot $RepoRoot `
            -RegistryPathOverride $RegistryPathOverride) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

function Test-TfsWorkflowViolation {
    <#
    Fails open (returns $false) whenever the origin remote cannot be
    determined -- git missing, no origin, timeout -- rather than blocking on
    an inconclusive check. Only blocks when the command text looks like a
    TFS/Azure DevOps operation AND the origin remote is confirmed GitHub.
    #>
    param(
        [string]$CommandText,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    if (-not $CommandText) { return $false }
    try {
        <#
        \b (not an anchored ^/;/&/| prefix) so a fully-qualified invocation
        like "C:\tools\tf.exe checkin" is still caught -- confirmed by
        testing that the original anchored version missed it entirely. \b
        alone is enough to avoid matching "tf" as a substring of an
        unrelated word, since it still requires "tf"/"tf.exe" to be
        followed by whitespace and one of the known subcommands.
        #>
        $looksLikeTfs = (
            $CommandText -match
                '(?i)\btf(\.exe)?\s+(checkin|checkout|get|merge|shelve)\b'
        ) -or (
            $CommandText -match '(?i)\baz\s+(repos|boards)\b'
        ) -or (
            $CommandText -match '(?i)(dev\.azure\.com|visualstudio\.com)'
        )
        if (-not $looksLikeTfs) { return $false }
        $url = & git -C $RepoRoot remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($url)) {
            return $false
        }
        return [bool]($url -match '(?i)github\.com')
    } catch {
        return $false
    }
}

function Test-DevSpaceLifecycleCommand {
    <#
    Rule 3 originally only matched tool names like mcp__devspace__* -- but
    DevSpace is actually bootstrapped via plain Bash/PowerShell commands
    (docker compose up against containers/devspace-isolation, a tunnel
    client pointed at its fixed port 7676), which never go through an
    mcp__devspace__* tool call at all. Matching on identifiers unique to this
    framework closes that gap: starting or managing the container stack, or
    starting a tunnel aimed at its fixed port/tunnel name, is gated the same
    as calling the MCP tools directly.

    The devtunnel and cloudflared patterns are both needed: this repo's own
    README documents Microsoft Dev Tunnel (devtunnel create/port create/
    access create/host, all against the fixed tunnel name
    "devspace-projectd") as the actual deployment, not Cloudflare -- a
    pattern list naming only "cloudflared tunnel" verifiably missed every
    real devtunnel command in that README.
    #>
    param([string]$CommandText)
    if (-not $CommandText) { return $false }
    try {
        return [bool](
            $CommandText -match '(?i)devspace-isolation' -or
            $CommandText -match '(?i)devspace-isolated' -or
            $CommandText -match '(?i)devspace-port-forward' -or
            $CommandText -match '(?i)devspace-egress-proxy' -or
            $CommandText -match '(?i)devspace-projectd' -or
            (
                $CommandText -match '(?i)cloudflared(\.exe)?\s+tunnel' -and
                $CommandText -match '7676'
            ) -or
            (
                $CommandText -match '(?i)devtunnel(\.exe)?\b' -and
                $CommandText -match '7676'
            )
        )
    } catch {
        return $false
    }
}

function Register-Classification {
    <#
    Writes a "personal"/"work" entry keyed by a sha256 digest into either the
    "repositories" bucket (this repo's origin remote) or the "machines"
    bucket (this computer's hostname). Never writes the raw identifier.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('repo', 'machine')][string]$Scope,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Classification,
        [string]$RegistryPathOverride
    )
    $hash = if ($Scope -ceq 'repo') {
        Get-NormalizedOriginHash -RepoRoot $RepoRoot
    } else {
        Get-NormalizedMachineHash
    }
    if (-not $hash) {
        $what = if ($Scope -ceq 'repo') { 'git origin remote' } else { '電腦名稱' }
        [Console]::Error.WriteLine("無法取得目前的 $what，登記失敗。")
        return 1
    }
    $registryPath = Get-ClassificationRegistryPath `
        -FallbackRoot $RepoRoot -OverridePath $RegistryPathOverride
    if (-not $registryPath) {
        [Console]::Error.WriteLine(
            '無法解析 projectD-core 位置（PROJECTD_CORE 未設定，且目前目錄不是 ' +
                'projectD-core），登記失敗。'
        )
        return 1
    }
    $document = if (Test-Path -LiteralPath $registryPath -PathType Leaf) {
        $text = [Text.Encoding]::UTF8.GetString(
            [IO.File]::ReadAllBytes($registryPath)
        )
        $text | ConvertFrom-Json
    } else {
        [pscustomobject]@{
            schema_version = 1
            repositories = [pscustomobject]@{}
            machines = [pscustomobject]@{}
            default = 'work'
        }
    }
    if ($document.PSObject.Properties.Name -notcontains 'machines') {
        $document | Add-Member `
            -NotePropertyName 'machines' -NotePropertyValue ([pscustomobject]@{})
    }
    $bucketName = if ($Scope -ceq 'repo') { 'repositories' } else { 'machines' }
    $bucket = $document.$bucketName
    if ($bucket.PSObject.Properties.Name -contains $hash) {
        $bucket.$hash = $Classification
    } else {
        $bucket | Add-Member `
            -NotePropertyName $hash -NotePropertyValue $Classification
    }
    New-Item -ItemType Directory -Force `
        -Path (Split-Path -Parent $registryPath) | Out-Null
    $json = $document | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText(
        $registryPath, $json, [Text.UTF8Encoding]::new($false)
    )
    "已將 $Scope $hash 登記為 $Classification（$registryPath）"
    return 0
}

if ($PSCmdlet.ParameterSetName -eq 'Register') {
    <#
    Registration requires a real interactive terminal, while direct edits
    and recognized command writes to project-classification.json are denied
    by the hook below. Tool-driven registration invocations
    (Claude Code's Bash tool, Codex, or any other non-interactive runner)
    have stdin redirected rather than attached to a console, so
    [Console]::IsInputRedirected is $true for them and $false for a human
    typing this command directly into their own terminal window. This is a
    deliberate deployment-specific answer to a threat-model question raised
    during review (accidental misclassification vs. an adversarial/
    prompt-injected agent) -- see docs/specs/governance-command-policy-hook.md
    addendum.
    #>
    if ([Console]::IsInputRedirected) {
        [Console]::Error.WriteLine(
            '登記只能在真正的互動式終端機裡執行，不能透過非互動的工具呼叫' +
                '（例如 AI agent 的 Bash 工具）完成。請直接在你自己開的終端機' +
                '視窗貼上同一行指令執行。'
        )
        exit 1
    }
    if ($RegisterCurrentRepo -and $RegisterCurrentMachine) {
        [Console]::Error.WriteLine(
            '-RegisterCurrentRepo 與 -RegisterCurrentMachine 不能同時使用。'
        )
        exit 1
    }
    if (-not $RegisterCurrentRepo -and -not $RegisterCurrentMachine) {
        [Console]::Error.WriteLine(
            '必須指定 -RegisterCurrentRepo 或 -RegisterCurrentMachine 其中之一。'
        )
        exit 1
    }
    $scope = if ($RegisterCurrentRepo) { 'repo' } else { 'machine' }
    $root = [IO.Path]::GetFullPath($ProjectRoot)
    exit (Register-Classification -Scope $scope -RepoRoot $root `
        -Classification $Classification -RegistryPathOverride $RegistryPath)
}

try {
    $stdinText = Read-BoundedStandardInput
    if ([string]::IsNullOrWhiteSpace($stdinText)) { exit 0 }
    $payload = $stdinText | ConvertFrom-Json
    if ([string]$payload.hook_event_name -cne 'PreToolUse') { exit 0 }

    $toolName = [string]$payload.tool_name
    $toolInput = $payload.tool_input
    $commandText = Get-CommandText -ToolInput $toolInput
    $root = [IO.Path]::GetFullPath($ProjectRoot)

    if (Test-AnonymousTunnelViolation -CommandText $commandText `
        -RepoRoot $root -RegistryPathOverride $RegistryPath) {
        Stop-HookOperation -Reason (
            'projectD 規則：禁止使用匿名公開 Tunnel（如 devtunnel ' +
                '--allow-anonymous）。已知例外：此 repository/機器登記為 ' +
                'personal 且透過 containers/devspace-isolation/ 隔離時可用；' +
                '其餘一律擋下，請改用已驗證的 Secure Tunnel 或受控 ' +
                'reverse proxy。'
        )
    }

    if (Test-TfsWorkflowViolation -CommandText $commandText -RepoRoot $root) {
        Stop-HookOperation -Reason (
            'projectD 規則：此 repository 的 remote 為 GitHub，不得使用 ' +
                'TFS/Azure DevOps 工作流程指令（tf/az repos/az boards）。' +
                '請先用「git remote -v」確認，改用 GitHub 工作流程。'
        )
    }

    if (Test-RegistryTamperViolation -ToolName $toolName -ToolInput $toolInput `
        -CommandText $commandText -RepoRoot $root `
        -RegistryPathOverride $RegistryPath) {
        Stop-HookOperation -Reason (
            'projectD 規則：不得直接編輯或寫入 personal/work 登記檔 ' +
                '（project-classification.json）。請用 ' +
                'governance-command-policy-hook.ps1 -RegisterCurrentRepo ' +
                '或 -RegisterCurrentMachine 在真正的互動式終端機登記。'
        )
    }

    $isDevSpaceCall = ($toolName -match '(?i)devspace') -or
        (Test-DevSpaceLifecycleCommand -CommandText $commandText)
    if ($isDevSpaceCall) {
        if (-not (Test-DevSpaceToolAllowed -RepoRoot $root `
            -RegistryPathOverride $RegistryPath)) {
            Stop-HookOperation -Reason (
                'projectD 規則：DevSpace（含其容器/tunnel 啟動指令）只能在 ' +
                    '登記為個人專案的 repository 或機器使用；目前未登記為 ' +
                    'personal，一律擋下。可用 -RegisterCurrentRepo 或 ' +
                    '-RegisterCurrentMachine 登記。'
            )
        }
    }

    exit 0
} catch {
    <#
    Outer protocol-level failure (malformed payload, oversized stdin): we
    cannot even determine the tool name, so rule 3's fail-closed guarantee
    cannot be evaluated here -- it only applies once Test-DevSpaceToolAllowed
    itself is reached and fails internally, which already fails closed on its
    own. This outer boundary fails open, matching rules 1 and 2.
    #>
    exit 0
}
