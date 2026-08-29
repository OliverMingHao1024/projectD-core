[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$hook = Join-Path $core 'scripts\governance-command-policy-hook.ps1'
$codexConfig = Join-Path $core '.codex\hooks.json'
$claudeConfig = Join-Path $core '.claude\settings.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "governance-command-policy-hook-$PID"
)
$repoRoot = Join-Path $tempRoot 'repo'
$registryPath = Join-Path $tempRoot 'project-classification.json'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

<#
Registration via the hook's own -RegisterCurrentRepo/-RegisterCurrentMachine
now requires a real interactive terminal (a deliberate fix -- see
docs/specs/governance-command-policy-hook.md addendum), which no automated
test harness has: this test file itself runs under pytest/CI with stdin
redirected, same as any tool-driven invocation. These two helpers replicate
the hook's own hashing (Get-NormalizedOriginHash/Get-NormalizedMachineHash)
to seed fixtures directly, so the interactive gate itself can be verified
(see the dedicated test below) without that gate blocking test setup.
#>
function Get-TestHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Normalized)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Normalized)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return 'sha256:' + [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-TestOriginHash {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $url = (& git -C $RepoRoot remote get-url origin 2>$null)
    $normalized = $url.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '^(https?://)[^@/]+@', '$1'
    $normalized = $normalized -replace '\.git/?$', ''
    $normalized = $normalized.TrimEnd('/')
    return Get-TestHash -Normalized $normalized
}

function Get-TestMachineHash {
    $name = [Environment]::MachineName
    return Get-TestHash -Normalized $name.Trim().ToLowerInvariant()
}

function Set-RegistryEntry {
    param(
        [Parameter(Mandatory)][ValidateSet('repositories', 'machines')][string]$Bucket,
        [Parameter(Mandatory)][string]$Hash,
        [Parameter(Mandatory)][string]$Classification,
        [Parameter(Mandatory)][string]$RegistryPath
    )
    $document = if (Test-Path -LiteralPath $RegistryPath -PathType Leaf) {
        Get-Content -Raw -LiteralPath $RegistryPath | ConvertFrom-Json
    } else {
        [pscustomobject]@{
            schema_version = 1
            repositories = [pscustomobject]@{}
            machines = [pscustomobject]@{}
            default = 'work'
        }
    }
    if ($document.PSObject.Properties.Name -notcontains $Bucket) {
        $document | Add-Member `
            -NotePropertyName $Bucket -NotePropertyValue ([pscustomobject]@{})
    }
    $bucketObject = $document.$Bucket
    if ($bucketObject.PSObject.Properties.Name -contains $Hash) {
        $bucketObject.$Hash = $Classification
    } else {
        $bucketObject | Add-Member `
            -NotePropertyName $Hash -NotePropertyValue $Classification
    }
    New-Item -ItemType Directory -Force `
        -Path (Split-Path -Parent $RegistryPath) | Out-Null
    $document | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $RegistryPath -Encoding utf8 -NoNewline
}

function Invoke-ScriptProcess {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$StandardInput = ''
    )
    $pwsh = Get-Command pwsh -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $ScriptPath) + $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($startInfo)
    $process.StandardInput.Write($StandardInput)
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(15000)
    if ($timedOut) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    [pscustomobject]@{
        ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        Stdout = $stdoutTask.GetAwaiter().GetResult()
        Stderr = $stderrTask.GetAwaiter().GetResult()
    }
}

function Invoke-PolicyHook {
    param(
        [Parameter(Mandatory)]$Payload,
        [string]$RepoRoot = $repoRoot,
        [string]$RegistryPath = $registryPath
    )
    return Invoke-ScriptProcess -ScriptPath $hook -Arguments @(
        '-ProjectRoot', $RepoRoot,
        '-RegistryPath', $RegistryPath
    ) -StandardInput ($Payload | ConvertTo-Json -Depth 32 -Compress)
}

function New-Payload {
    param(
        [string]$Event = 'PreToolUse',
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)]$ToolInput
    )
    return [pscustomobject][ordered]@{
        hook_event_name = $Event
        session_id = 'contract-session'
        tool_use_id = 'contract-call'
        tool_name = $ToolName
        tool_input = $ToolInput
    }
}

try {
    New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
    & git -C $repoRoot init --quiet | Out-Null
    & git -C $repoRoot remote add origin `
        'https://github.com/example-owner/example-repo.git' | Out-Null

    Assert-True (Test-Path -LiteralPath $hook -PathType Leaf) (
        'The command policy hook must exist.'
    )

    # Rule 1: anonymous tunnel is always blocked, regardless of registry state.
    $tunnelPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'devtunnel host -p 3000 --allow-anonymous'
    })
    $tunnelResult = Invoke-PolicyHook -Payload $tunnelPayload
    Assert-True ($tunnelResult.ExitCode -eq 2) (
        "Anonymous tunnel command must be blocked: $($tunnelResult.Stderr)"
    )
    Assert-True (-not [string]::IsNullOrWhiteSpace($tunnelResult.Stderr)) (
        'A blocked call must explain why on stderr.'
    )

    # Regression cases: devtunnel grants anonymous access via more than one
    # spelling, all of which must be caught, not just the long
    # --allow-anonymous flag on `host`.
    $shortFlagPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'devtunnel host devspace-projectd -p 7676 -a'
    })
    $shortFlagResult = Invoke-PolicyHook -Payload $shortFlagPayload
    Assert-True ($shortFlagResult.ExitCode -eq 2) (
        "The -a short flag must be treated the same as --allow-anonymous: " +
            $shortFlagResult.Stderr
    )

    $accessCreatePayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'devtunnel access create devspace-projectd -p 7676 --anonymous'
    })
    $accessCreateResult = Invoke-PolicyHook -Payload $accessCreatePayload
    Assert-True ($accessCreateResult.ExitCode -eq 2) (
        "'access create ... --anonymous' (no allow- prefix) must be " +
            "treated the same as --allow-anonymous: " +
            $accessCreateResult.Stderr
    )

    # A stray "-a" on some unrelated command must not false-positive just
    # because the word "devtunnel" also appears somewhere in the line.
    $strayFlagPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'echo "devtunnel notes" && ls -a'
    })
    $strayFlagResult = Invoke-PolicyHook -Payload $strayFlagPayload
    Assert-True ($strayFlagResult.ExitCode -eq 0) (
        'An unrelated -a flag must not be treated as --allow-anonymous.'
    )

    $safeTunnelPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'devtunnel host -p 3000'
    })
    $safeTunnelResult = Invoke-PolicyHook -Payload $safeTunnelPayload
    Assert-True ($safeTunnelResult.ExitCode -eq 0) (
        'devtunnel without --allow-anonymous must be allowed.'
    )

    # Rule 2: TFS-style commands are blocked only when origin resolves to GitHub.
    $tfsPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'az repos pr create --title "test"'
    })
    $tfsResult = Invoke-PolicyHook -Payload $tfsPayload
    Assert-True ($tfsResult.ExitCode -eq 2) (
        "TFS-style command on a GitHub-remote repo must be blocked: " +
            $tfsResult.Stderr
    )

    $nonTfsRepoRoot = Join-Path $tempRoot 'repo-no-origin'
    New-Item -ItemType Directory -Path $nonTfsRepoRoot -Force | Out-Null
    & git -C $nonTfsRepoRoot init --quiet | Out-Null
    $tfsNoOriginResult = Invoke-PolicyHook -Payload $tfsPayload `
        -RepoRoot $nonTfsRepoRoot
    Assert-True ($tfsNoOriginResult.ExitCode -eq 0) (
        'An undeterminable origin remote must fail open (allow), not block.'
    )

    $ordinaryPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'git status'
    })
    $ordinaryResult = Invoke-PolicyHook -Payload $ordinaryPayload
    Assert-True ($ordinaryResult.ExitCode -eq 0) (
        'An ordinary command must be allowed.'
    )

    # Regression: a fully-qualified tf.exe invocation must still be caught,
    # not just one anchored at the start of the command or after ;/&&/||/|.
    $tfsFullPathPayload = New-Payload -ToolName 'Bash' -ToolInput (
        [pscustomobject]@{ command = 'C:\tools\tf.exe checkin /comment:test' }
    )
    $tfsFullPathResult = Invoke-PolicyHook -Payload $tfsFullPathPayload
    Assert-True ($tfsFullPathResult.ExitCode -eq 2) (
        "A fully-qualified tf.exe path must still be detected: " +
            $tfsFullPathResult.Stderr
    )

    # Rule 3: DevSpace MCP is denied by default (registry missing).
    $devspacePayload = New-Payload -ToolName 'mcp__devspace__run_shell' `
        -ToolInput ([pscustomobject]@{ command = 'echo hi' })
    $missingRegistryResult = Invoke-PolicyHook -Payload $devspacePayload
    Assert-True ($missingRegistryResult.ExitCode -eq 2) (
        "DevSpace must be denied when the registry file is missing: " +
            $missingRegistryResult.Stderr
    )

    $emptyRegistry = [pscustomobject]@{
        schema_version = 1
        repositories = [pscustomobject]@{}
        default = 'work'
    }
    $emptyRegistry | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $registryPath -Encoding utf8 -NoNewline
    $unregisteredResult = Invoke-PolicyHook -Payload $devspacePayload
    Assert-True ($unregisteredResult.ExitCode -eq 2) (
        'DevSpace must be denied for a repository absent from the registry.'
    )

    $malformedRegistryPath = Join-Path $tempRoot 'malformed-registry.json'
    Set-Content -LiteralPath $malformedRegistryPath -Value '{ not valid json' `
        -Encoding utf8 -NoNewline
    $malformedResult = Invoke-PolicyHook -Payload $devspacePayload `
        -RegistryPath $malformedRegistryPath
    Assert-True ($malformedResult.ExitCode -eq 2) (
        'DevSpace must be denied when the registry cannot be parsed.'
    )

    # Register the fixture repo as personal (directly -- see Set-RegistryEntry
    # above for why this no longer goes through the CLI), then confirm
    # DevSpace is allowed.
    Set-RegistryEntry -Bucket 'repositories' `
        -Hash (Get-TestOriginHash -RepoRoot $repoRoot) `
        -Classification 'personal' -RegistryPath $registryPath
    $allowedResult = Invoke-PolicyHook -Payload $devspacePayload
    Assert-True ($allowedResult.ExitCode -eq 0) (
        "DevSpace must be allowed once the repository is registered personal: " +
            $allowedResult.Stderr
    )
    $registryDocument = Get-Content -Raw -LiteralPath $registryPath |
        ConvertFrom-Json
    Assert-True (
        -not (Get-Content -Raw -LiteralPath $registryPath).Contains(
            'example-owner/example-repo'
        )
    ) 'The registry must never contain the plaintext remote URL.'
    $registeredHash = @(
        $registryDocument.repositories.PSObject.Properties.Name
    )[0]
    Assert-True ($registeredHash -like 'sha256:*') (
        'Registered repositories must be keyed by a sha256 digest.'
    )

    # A repository explicitly registered "work" is still denied.
    $workRepoRoot = Join-Path $tempRoot 'repo-work'
    New-Item -ItemType Directory -Path $workRepoRoot -Force | Out-Null
    & git -C $workRepoRoot init --quiet | Out-Null
    & git -C $workRepoRoot remote add origin `
        'https://github.com/example-owner/work-repo.git' | Out-Null
    Set-RegistryEntry -Bucket 'repositories' `
        -Hash (Get-TestOriginHash -RepoRoot $workRepoRoot) `
        -Classification 'work' -RegistryPath $registryPath
    $workDeniedResult = Invoke-PolicyHook -Payload $devspacePayload `
        -RepoRoot $workRepoRoot
    Assert-True ($workDeniedResult.ExitCode -eq 2) (
        'DevSpace must remain denied for a repository explicitly registered work.'
    )

    # Rule 3 also matches plain Bash/PowerShell commands that bootstrap or
    # manage the container/tunnel by name, not just mcp__devspace__* tool
    # calls -- this is how DevSpace actually gets started in practice.
    $composeUpPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'cd containers/devspace-isolation && docker compose up -d'
    })
    $composeUpDeniedResult = Invoke-PolicyHook -Payload $composeUpPayload `
        -RepoRoot $workRepoRoot
    Assert-True ($composeUpDeniedResult.ExitCode -eq 2) (
        "Starting the devspace-isolation compose stack via Bash must be " +
            "denied on a work-registered repo: " + $composeUpDeniedResult.Stderr
    )
    $composeUpAllowedResult = Invoke-PolicyHook -Payload $composeUpPayload
    Assert-True ($composeUpAllowedResult.ExitCode -eq 0) (
        "Starting the devspace-isolation compose stack via Bash must be " +
            "allowed on the personal-registered repo: " +
            $composeUpAllowedResult.Stderr
    )

    $tunnelPayload2 = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'cloudflared tunnel --url http://127.0.0.1:7676'
    })
    $tunnelDeniedResult = Invoke-PolicyHook -Payload $tunnelPayload2 `
        -RepoRoot $workRepoRoot
    Assert-True ($tunnelDeniedResult.ExitCode -eq 2) (
        "Starting a cloudflared tunnel at DevSpace's fixed port must be " +
            "denied on a work-registered repo: " + $tunnelDeniedResult.Stderr
    )

    $unrelatedTunnelPayload = New-Payload -ToolName 'Bash' -ToolInput (
        [pscustomobject]@{
            command = 'cloudflared tunnel --url http://127.0.0.1:9999'
        }
    )
    $unrelatedTunnelResult = Invoke-PolicyHook -Payload $unrelatedTunnelPayload `
        -RepoRoot $workRepoRoot
    Assert-True ($unrelatedTunnelResult.ExitCode -eq 0) (
        'A cloudflared tunnel pointed at an unrelated port must not be ' +
            'treated as a DevSpace lifecycle command.'
    )

    # Regression: the actual devtunnel commands this repo's README
    # documents (not cloudflared) must also be recognized as DevSpace
    # lifecycle commands, on a work-registered repo.
    foreach ($devtunnelCommand in @(
        'devtunnel create devspace-projectd',
        'devtunnel port create devspace-projectd -p 7676 --protocol http',
        'devtunnel access create devspace-projectd -p 7676 --anonymous',
        'devtunnel host devspace-projectd'
    )) {
        $devtunnelPayload = New-Payload -ToolName 'Bash' -ToolInput (
            [pscustomobject]@{ command = $devtunnelCommand }
        )
        $devtunnelResult = Invoke-PolicyHook -Payload $devtunnelPayload `
            -RepoRoot $workRepoRoot
        Assert-True ($devtunnelResult.ExitCode -eq 2) (
            "devtunnel lifecycle command must be denied on a work-" +
                "registered repo: '$devtunnelCommand' -- " +
                $devtunnelResult.Stderr
        )
    }

    # ADR 0017: devtunnel --allow-anonymous is exempted only for a
    # personal-registered repo/machine; a work-registered one stays blocked.
    $anonTunnelPayload = New-Payload -ToolName 'Bash' -ToolInput ([pscustomobject]@{
        command = 'devtunnel host -p 7676 --allow-anonymous'
    })
    $anonTunnelAllowedResult = Invoke-PolicyHook -Payload $anonTunnelPayload
    Assert-True ($anonTunnelAllowedResult.ExitCode -eq 0) (
        "devtunnel --allow-anonymous must be exempted on a personal-" +
            "registered repo: " + $anonTunnelAllowedResult.Stderr
    )
    $anonTunnelDeniedResult = Invoke-PolicyHook -Payload $anonTunnelPayload `
        -RepoRoot $workRepoRoot
    Assert-True ($anonTunnelDeniedResult.ExitCode -eq 2) (
        'devtunnel --allow-anonymous must remain blocked on a work-' +
            'registered repo.'
    )

    # Machine-level registration is a fallback for repos never individually
    # registered, and never stores the raw hostname.
    $machineRepoRoot = Join-Path $tempRoot 'repo-machine-fallback'
    New-Item -ItemType Directory -Path $machineRepoRoot -Force | Out-Null
    & git -C $machineRepoRoot init --quiet | Out-Null
    & git -C $machineRepoRoot remote add origin `
        'https://github.com/example-owner/machine-fallback-repo.git' | Out-Null
    $machineDeniedResult = Invoke-PolicyHook -Payload $devspacePayload `
        -RepoRoot $machineRepoRoot
    Assert-True ($machineDeniedResult.ExitCode -eq 2) (
        'DevSpace must remain denied when neither the repo nor the machine ' +
            'is registered.'
    )

    Set-RegistryEntry -Bucket 'machines' -Hash (Get-TestMachineHash) `
        -Classification 'personal' -RegistryPath $registryPath
    $machineAllowedResult = Invoke-PolicyHook -Payload $devspacePayload `
        -RepoRoot $machineRepoRoot
    Assert-True ($machineAllowedResult.ExitCode -eq 0) (
        "DevSpace must be allowed via machine-level registration for an " +
            "unregistered repo: " + $machineAllowedResult.Stderr
    )
    Assert-True (
        -not (Get-Content -Raw -LiteralPath $registryPath).Contains(
            [Environment]::MachineName
        )
    ) 'The registry must never contain the plaintext machine name.'

    # Repo-level registration takes precedence over machine-level.
    $overrideResult = Invoke-PolicyHook -Payload $devspacePayload `
        -RepoRoot $workRepoRoot
    Assert-True ($overrideResult.ExitCode -eq 2) (
        'An explicit repo-level "work" registration must still win over an ' +
            'allowing machine-level registration.'
    )

    # Non-Bash/PowerShell, non-DevSpace tools are always unaffected.
    $readPayload = New-Payload -ToolName 'Read' -ToolInput ([pscustomobject]@{
        file_path = 'fixture.txt'
    })
    $readResult = Invoke-PolicyHook -Payload $readPayload
    Assert-True ($readResult.ExitCode -eq 0) (
        'Non-shell, non-DevSpace tools must never be blocked.'
    )

    # PostToolUse events are ignored entirely (PreToolUse-only enforcement).
    $postPayload = New-Payload -Event 'PostToolUse' -ToolName 'Bash' `
        -ToolInput ([pscustomobject]@{
            command = 'devtunnel host --allow-anonymous'
        })
    $postResult = Invoke-PolicyHook -Payload $postPayload
    Assert-True ($postResult.ExitCode -eq 0) (
        'PostToolUse events must not be evaluated by this PreToolUse-only hook.'
    )

    # Malformed stdin must fail open entirely (outer protocol boundary).
    $malformedStdinResult = Invoke-ScriptProcess -ScriptPath $hook -Arguments @(
        '-ProjectRoot', $repoRoot, '-RegistryPath', $registryPath
    ) -StandardInput '{ not valid json'
    Assert-True ($malformedStdinResult.ExitCode -eq 0) (
        'Malformed stdin must fail open rather than block the tool call.'
    )

    # Registration must require a real interactive terminal -- confirmed by
    # invoking it the same way this whole test file invokes everything else
    # (a redirected-stdin child process), which is also how any tool-driven
    # invocation (Claude Code's Bash tool, Codex, etc.) looks. This test
    # cannot exercise the "allowed" path: no automated harness has a real
    # console to attach, by design -- that's the point of the check.
    $nonInteractiveRegisterResult = Invoke-ScriptProcess -ScriptPath $hook `
        -Arguments @(
            '-RegisterCurrentMachine', '-Classification', 'personal',
            '-ProjectRoot', $repoRoot, '-RegistryPath', $registryPath
        ) -StandardInput ''
    Assert-True ($nonInteractiveRegisterResult.ExitCode -eq 1) (
        "Registration via a non-interactive (redirected-stdin) invocation " +
            "must be refused: " + $nonInteractiveRegisterResult.Stderr
    )
    Assert-True (-not [string]::IsNullOrWhiteSpace(
        $nonInteractiveRegisterResult.Stderr
    )) 'A refused non-interactive registration must explain why.'

    # Security review follow-up: project-classification.json had no
    # integrity protection at all -- anything with filesystem write access
    # could edit it directly to grant "personal" and bypass rule 3 and the
    # anonymous-tunnel exception, without ever going through the now-
    # interactive-only registration commands. An Edit/Write/NotebookEdit
    # call whose target path resolves to the registry file must be blocked.
    $editRegistryPayload = New-Payload -ToolName 'Edit' -ToolInput (
        [pscustomobject]@{
            file_path   = $registryPath
            old_string  = 'work'
            new_string  = 'personal'
        }
    )
    $editRegistryResult = Invoke-PolicyHook -Payload $editRegistryPayload
    Assert-True ($editRegistryResult.ExitCode -eq 2) (
        "Editing the registry file directly must be blocked: " +
            $editRegistryResult.Stderr
    )

    # A Bash/PowerShell command that names the registry file alongside a
    # recognizable write/redirect indicator must also be blocked.
    $bashWriteRegistryPayload = New-Payload -ToolName 'Bash' -ToolInput (
        [pscustomobject]@{
            command = "echo '{}' > `"$registryPath`""
        }
    )
    $bashWriteRegistryResult = Invoke-PolicyHook `
        -Payload $bashWriteRegistryPayload
    Assert-True ($bashWriteRegistryResult.ExitCode -eq 2) (
        "A shell command writing to the registry file must be blocked: " +
            $bashWriteRegistryResult.Stderr
    )

    # Regression: a plain read of the registry file must still be allowed.
    $readRegistryPayload = New-Payload -ToolName 'Bash' -ToolInput (
        [pscustomobject]@{ command = "cat `"$registryPath`"" }
    )
    $readRegistryResult = Invoke-PolicyHook -Payload $readRegistryPayload
    Assert-True ($readRegistryResult.ExitCode -eq 0) (
        "A plain read of the registry file must remain allowed: " +
            $readRegistryResult.Stderr
    )

    # Regression: editing an unrelated file must still be allowed.
    $editUnrelatedPayload = New-Payload -ToolName 'Edit' -ToolInput (
        [pscustomobject]@{
            file_path  = (Join-Path $tempRoot 'unrelated.md')
            old_string = 'a'
            new_string = 'b'
        }
    )
    $editUnrelatedResult = Invoke-PolicyHook -Payload $editUnrelatedPayload
    Assert-True ($editUnrelatedResult.ExitCode -eq 0) (
        "Editing an unrelated file must remain allowed: " +
            $editUnrelatedResult.Stderr
    )

    Assert-True (Test-Path -LiteralPath $codexConfig -PathType Leaf) (
        'Codex repository hook configuration must exist.'
    )
    Assert-True (Test-Path -LiteralPath $claudeConfig -PathType Leaf) (
        'Claude repository hook configuration must exist.'
    )
    $codex = Get-Content -Raw -LiteralPath $codexConfig | ConvertFrom-Json
    $codexPreEntries = @($codex.hooks.PreToolUse)
    $codexPreCommandText = (@($codexPreEntries | ForEach-Object {
        @($_.hooks) | ForEach-Object { [string]$_.command }
    })) -join "`n"
    $codexHasPolicyHook = $codexPreCommandText.Contains(
        'governance-command-policy-hook.ps1'
    )
    Assert-True $codexHasPolicyHook (
        'Codex PreToolUse must also invoke the command policy hook.'
    )

    $claude = Get-Content -Raw -LiteralPath $claudeConfig | ConvertFrom-Json
    $claudePreEntries = @($claude.hooks.PreToolUse)
    $claudePreArgText = (@($claudePreEntries | ForEach-Object {
        @($_.hooks) | ForEach-Object { ([string[]]$_.args) -join ' ' }
    })) -join "`n"
    $claudeHasPolicyHook = $claudePreArgText.Contains(
        'governance-command-policy-hook.ps1'
    )
    Assert-True $claudeHasPolicyHook (
        'Claude PreToolUse must also invoke the command policy hook.'
    )

    '[PASS] anonymous tunnel commands are blocked'
    '[PASS] TFS-style commands are blocked only on a confirmed GitHub remote'
    '[PASS] DevSpace MCP is denied unless the repository is registered personal'
    '[PASS] machine-level registration is a fallback that repo-level overrides'
    '[PASS] DevSpace lifecycle Bash commands (compose/cloudflared) are gated too'
    '[PASS] anonymous devtunnel is exempted only on a personal-registered repo/machine'
    '[PASS] anonymous-tunnel detection covers -a and access-create --anonymous too'
    '[PASS] devtunnel lifecycle commands (not just cloudflared) are gated too'
    '[PASS] registry never stores plaintext remote identifiers or hostnames'
    '[PASS] a fully-qualified tf.exe path is still detected'
    '[PASS] editing the registry file directly is blocked'
    '[PASS] a shell command writing to the registry file is blocked'
    '[PASS] a plain read of the registry file remains allowed'
    '[PASS] editing an unrelated file remains allowed'
    '[PASS] non-shell/non-DevSpace tools and PostToolUse are unaffected'
    '[PASS] malformed stdin fails open'
    '[PASS] registration requires a real interactive terminal, not a redirected-stdin call'
    '[PASS] Codex and Claude hook configs both wire the command policy hook'
} finally {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    if (
        (Test-Path -LiteralPath $resolvedTempRoot) -and
        $resolvedTempRoot.StartsWith(
            $tempBase, [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Split-Path $resolvedTempRoot -Leaf) -like
            'governance-command-policy-hook-*'
    ) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
