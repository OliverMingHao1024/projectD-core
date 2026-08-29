<#
Verifies the isolation posture required by
docs/adr/0015-isolate-ai-agent-mcp-server-execution.md and
docs/specs/devspace-isolation-container-framework.md.

Runs on the host; drives the containers via `docker compose exec` rather than
requiring a second in-container script. Brings the stack up, checks five
things, tears the stack back down (including the scratch repo directory it
creates for the bind-mount), and reports PASS/FAIL per check with a non-zero
exit code if anything failed.
#>

[CmdletBinding()]
param(
    [string]$RepoPath = (Join-Path ([IO.Path]::GetTempPath()) (
        "devspace-isolation-verify-$PID"
    ))
)

$ErrorActionPreference = 'Stop'
$composeDir = Split-Path -Parent $PSScriptRoot
$results = [Collections.Generic.List[pscustomobject]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Detail = ''
    )
    $results.Add([pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    })
}

function Invoke-InContainer {
    param([Parameter(Mandatory)][string]$Command)
    return (docker compose exec -T devspace sh -c $Command 2>&1) -join "`n"
}

New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null
$env:DEVSPACE_REPO_PATH = $RepoPath
# Verification-only throwaway Owner token -- never the real deployment
# secret. Compose requires the variable to be set at all.
$env:DEVSPACE_OAUTH_OWNER_TOKEN = [Guid]::NewGuid().ToString('N')

Push-Location $composeDir
try {
    docker compose up -d --build 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'docker compose up failed -- see docker compose logs for detail.'
    }
    Start-Sleep -Seconds 2

    # 1. No host credential paths are reachable from inside the container.
    $credOutput = Invoke-InContainer (
        'for p in $HOME/.ssh $HOME/.aws $HOME/.kube /root/.ssh /root/.aws ' +
        '/root/.kube; do [ -e "$p" ] && echo "FOUND:$p"; done; true'
    )
    Add-Result 'no-host-credential-paths' ([string]::IsNullOrWhiteSpace(
        $credOutput
    )) $credOutput

    # 2. No Docker socket is present inside the container.
    $socketOutput = Invoke-InContainer (
        '[ -e /var/run/docker.sock ] && echo FOUND || echo ABSENT'
    )
    Add-Result 'no-docker-socket' ($socketOutput.Trim() -eq 'ABSENT') `
        $socketOutput

    # 3. Direct egress (bypassing the proxy) fails -- the internal network
    #    has no route out regardless of what any future DevSpace software
    #    configures for its own proxy settings.
    $directOutput = Invoke-InContainer (
        'curl --max-time 5 -s -o /dev/null --noproxy "*" ' +
        'http://example.com; echo "exit=$?"'
    )
    Add-Result 'no-direct-egress' ($directOutput -notmatch 'exit=0') `
        $directOutput

    # 4. A proxied request to a domain NOT on the allowlist is denied by
    #    Squid (not merely unreachable -- this proves policy enforcement,
    #    not just network topology).
    $deniedOutput = Invoke-InContainer (
        'curl --max-time 5 -s -o /dev/null -w "%{http_code}" ' +
        '-x http://egress-proxy:3128 http://denied-test.invalid.example/'
    )
    Add-Result 'proxy-denies-nonallowed-domain' (
        $deniedOutput.Trim() -eq '403'
    ) "http_code=$($deniedOutput.Trim())"

    # 5. A proxied request to the allowlisted verification domain succeeds.
    $allowedOutput = Invoke-InContainer (
        'curl --max-time 5 -s -o /dev/null -w "%{http_code}" ' +
        '-x http://egress-proxy:3128 http://example.com/'
    )
    Add-Result 'proxy-allows-allowlisted-domain' (
        $allowedOutput.Trim() -match '^(200|301|302)$'
    ) "http_code=$($allowedOutput.Trim())"

    # 6. The real DevSpace MCP server is actually listening and answering
    #    HTTP on the published host-loopback port -- proves the isolation
    #    posture above holds with the real software running, not just the
    #    earlier placeholder.
    $deadline = (Get-Date).AddSeconds(20)
    $mcpReachable = $false
    $mcpDetail = 'timed out waiting for a response'
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:7676/mcp' `
                -Method Get -TimeoutSec 5 -SkipHttpErrorCheck -ErrorAction Stop
            $mcpReachable = $true
            $mcpDetail = "http_status=$($response.StatusCode)"
            break
        } catch {
            $mcpDetail = $_.Exception.Message
            Start-Sleep -Seconds 2
        }
    }
    Add-Result 'devspace-mcp-endpoint-responds' $mcpReachable $mcpDetail
} finally {
    docker compose down -v 2>&1 | Out-Null
    Pop-Location
    Remove-Item -LiteralPath $RepoPath -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($result in $results) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    $detail = if ($result.Detail) { " -- $($result.Detail)" } else { '' }
    "[$status] $($result.Name)$detail"
}

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
    "`n$($failed.Count) of $($results.Count) checks failed."
    exit 1
}
"`nAll $($results.Count) checks passed."
exit 0
