<#
Verifies the isolation posture required by
docs/adr/0015-isolate-ai-agent-mcp-server-execution.md and
docs/specs/devspace-isolation-container-framework.md.

Runs on the host; drives the containers via `docker compose exec` rather than
requiring a second in-container script. Brings the stack up, checks nine
things, tears the stack back down (including the two scratch repo
directories it creates for the multi-repo bind-mounts), and reports
PASS/FAIL per check with a non-zero exit code if anything failed.
#>

[CmdletBinding()]
param(
    [string]$RepoPathA = (Join-Path ([IO.Path]::GetTempPath()) (
        "devspace-isolation-verify-a-$PID"
    )),
    [string]$RepoPathB = (Join-Path ([IO.Path]::GetTempPath()) (
        "devspace-isolation-verify-b-$PID"
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

New-Item -ItemType Directory -Path $RepoPathA -Force | Out-Null
New-Item -ItemType Directory -Path $RepoPathB -Force | Out-Null
# Something distinguishable in each scratch repo, so check 7 below can prove
# the two /repos/* mounts are not somehow the same directory or swapped.
Set-Content -LiteralPath (Join-Path $RepoPathA 'marker-a.txt') -Value 'a'
Set-Content -LiteralPath (Join-Path $RepoPathB 'marker-b.txt') -Value 'b'
$env:DEVSPACE_REPO_PATH_PROJECTD_CORE = $RepoPathA
$env:DEVSPACE_REPO_PATH_CHOUTEN_COURT = $RepoPathB
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

    # 7. egress-proxy runs with the full capability drop too, same as
    #    devspace/port-forward -- it starts as uid/gid 13 (squid's own
    #    "proxy" user) instead of relying on squid to setgid/initgroups
    #    itself internally, which cap_drop: ALL would otherwise block.
    $capOutput = (docker compose exec -T egress-proxy sh -c `
        'cat /proc/1/status' 2>&1) -join "`n"
    $capLines = $capOutput -split "`n" | Where-Object { $_ -match '^Cap\w+:' }
    $nonZeroCaps = $capLines | Where-Object { $_ -notmatch ':\s*0+$' }
    Add-Result 'egress-proxy-has-no-capabilities' (
        $capLines.Count -gt 0 -and $nonZeroCaps.Count -eq 0
    ) ($capLines -join ' | ')

    # 8. Multi-repo mounts land in the right place and don't cross-contaminate
    #    -- each scratch repo's own marker file is visible only under its own
    #    /repos/<name> path, and DEVSPACE_ALLOWED_ROOTS actually lists both.
    $markerAOutput = Invoke-InContainer (
        '[ -f /repos/projectD-core/marker-a.txt ] && ' +
        '[ ! -f /repos/projectD-core/marker-b.txt ] && echo OK || echo WRONG'
    )
    $markerBOutput = Invoke-InContainer (
        '[ -f /repos/chouten-court/marker-b.txt ] && ' +
        '[ ! -f /repos/chouten-court/marker-a.txt ] && echo OK || echo WRONG'
    )
    Add-Result 'multi-repo-mounts-not-cross-contaminated' (
        $markerAOutput.Trim() -eq 'OK' -and $markerBOutput.Trim() -eq 'OK'
    ) "projectD-core=$($markerAOutput.Trim()) chouten-court=$($markerBOutput.Trim())"

    $rootsOutput = Invoke-InContainer (
        'cat /proc/1/environ | tr "\0" "\n" | grep ^DEVSPACE_ALLOWED_ROOTS='
    )
    Add-Result 'allowed-roots-lists-both-repos' (
        $rootsOutput -match '/repos/projectD-core' -and
        $rootsOutput -match '/repos/chouten-court'
    ) $rootsOutput.Trim()
} finally {
    docker compose down -v 2>&1 | Out-Null
    Pop-Location
    Remove-Item -LiteralPath $RepoPathA -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $RepoPathB -Recurse -Force -ErrorAction SilentlyContinue
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
