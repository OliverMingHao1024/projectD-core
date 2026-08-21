[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Status', 'Prepare', 'Verify')]
    [string]$Action,
    [string]$Target,
    [string]$ProfilesPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'claude-account-core.ps1')

function Test-PresentEnvironmentValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    return $normalized -notin @('', '0', 'false', 'no', 'off')
}

function Get-LiveClaudeAuthStatus {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        throw 'Claude CLI is unavailable.'
    }
    $raw = @(& claude auth status --json 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        throw 'Claude authentication status is unavailable.'
    }
    return $raw | ConvertFrom-Json
}

$auth = $null
try {
    $auth = Get-LiveClaudeAuthStatus
} catch {
    Write-Verbose "Auth status check failed: $($_.Exception.Message)"
}
$environmentState = [pscustomobject]@{
    apiBilling = (
        (Test-PresentEnvironmentValue $env:ANTHROPIC_API_KEY) -or
        (Test-PresentEnvironmentValue $env:ANTHROPIC_AUTH_TOKEN) -or
        (Test-PresentEnvironmentValue $env:CLAUDE_CODE_OAUTH_TOKEN)
    )
    thirdParty = (
        (Test-PresentEnvironmentValue $env:CLAUDE_CODE_USE_BEDROCK) -or
        (Test-PresentEnvironmentValue $env:CLAUDE_CODE_USE_VERTEX) -or
        (Test-PresentEnvironmentValue $env:CLAUDE_CODE_USE_FOUNDRY)
    )
}

$result = Invoke-ClaudeAccountAssessment `
    -Action $Action `
    -Auth $auth `
    -EnvironmentState $environmentState `
    -Target $Target `
    -ProfilesPath $ProfilesPath
$result | ConvertTo-Json -Depth 6 -Compress
if (-not $result.passed) { exit 1 }
