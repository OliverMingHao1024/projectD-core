[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$coreScript = Join-Path $core 'core\skills\claude-switch-account\scripts\claude-account-core.ps1'
. $coreScript
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "claude-switch-account-$PID"
$profilesPath = Join-Path $tempRoot 'profiles.json'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Value
    )
    $Value | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $Path `
        -Encoding utf8 `
        -NoNewline
}

function Invoke-Contract {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Target,
        [Parameter(Mandatory)][string]$AuthStatusPath,
        [string]$Profiles = $profilesPath
    )
    $auth = Get-Content -Raw -LiteralPath $AuthStatusPath | ConvertFrom-Json
    $environmentState = [pscustomobject]@{
        apiBilling = (
            [bool]$auth.environment.anthropic_api_key -or
            [bool]$auth.environment.anthropic_auth_token -or
            [bool]$auth.environment.claude_code_oauth_token
        )
        thirdParty = (
            [bool]$auth.environment.bedrock -or
            [bool]$auth.environment.vertex -or
            [bool]$auth.environment.foundry
        )
    }
    Invoke-ClaudeAccountAssessment `
        -Action $Action `
        -Auth $auth `
        -EnvironmentState $environmentState `
        -Target $Target `
        -ProfilesPath $Profiles
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-JsonFixture -Path $profilesPath -Value @{
        schema_version = 1
        subscription_only = $true
        profiles = @(
            @{
                alias = 'work'
                aliases = @('工作')
                email = 'work@example.test'
            },
            @{
                alias = 'personal'
                aliases = @('個人')
                email = 'personal@example.test'
            }
        )
    }

    $workAuth = Join-Path $tempRoot 'work-auth.json'
    Write-JsonFixture -Path $workAuth -Value @{
        loggedIn = $true
        authMethod = 'claude.ai'
        apiProvider = 'firstParty'
        subscriptionType = 'team'
        email = 'work@example.test'
        orgName = 'Systex-F25B'
        environment = @{
            anthropic_api_key = $false
            anthropic_auth_token = $false
            claude_code_oauth_token = $false
            bedrock = $false
            vertex = $false
            foundry = $false
        }
    }

    $personalAuth = Join-Path $tempRoot 'personal-auth.json'
    Write-JsonFixture -Path $personalAuth -Value @{
        loggedIn = $true
        authMethod = 'claude.ai'
        apiProvider = 'firstParty'
        subscriptionType = 'pro'
        email = 'personal@example.test'
        orgName = 'Personal'
        environment = @{
            anthropic_api_key = $false
            anthropic_auth_token = $false
            claude_code_oauth_token = $false
            bedrock = $false
            vertex = $false
            foundry = $false
        }
    }

    $status = Invoke-Contract -Action Status -AuthStatusPath $workAuth
    Assert-True $status.passed 'Safe subscription status must pass.'
    Assert-True (
        $status.current.email -eq 'work@example.test'
    ) 'Status must report the active email.'

    $prepare = Invoke-Contract `
        -Action Prepare `
        -Target '個人' `
        -AuthStatusPath $workAuth
    Assert-True $prepare.passed 'A safe switch preparation must pass.'
    Assert-True $prepare.ready_to_switch 'A different safe account must be ready.'
    Assert-True (
        $prepare.target.alias -eq 'personal'
    ) 'Chinese alias must resolve to personal.'
    Assert-True (
        $prepare.target.email -eq 'personal@example.test'
    ) 'Target email must be resolved locally.'
    Assert-True (
        -not (($prepare | ConvertTo-Json -Depth 8) -match '(?i)token|api[_-]?key')
    ) 'Sanitized output must not expose secret field names.'

    $mismatch = Invoke-Contract `
        -Action Verify `
        -Target personal `
        -AuthStatusPath $workAuth
    Assert-True (-not $mismatch.passed) 'Wrong active account must fail verification.'
    Assert-True (
        @($mismatch.blockers) -contains 'active-account-does-not-match-target'
    ) 'Mismatch must return a stable blocker.'

    $verified = Invoke-Contract `
        -Action Verify `
        -Target personal `
        -AuthStatusPath $personalAuth
    Assert-True $verified.passed 'Correct personal subscription must verify.'
    Assert-True $verified.already_active 'Verified target must be active.'

    $apiAuth = Join-Path $tempRoot 'api-auth.json'
    $apiFixture = Get-Content -Raw $workAuth | ConvertFrom-Json -AsHashtable
    $apiFixture.environment.anthropic_api_key = $true
    Write-JsonFixture -Path $apiAuth -Value $apiFixture
    $apiBlocked = Invoke-Contract -Action Status -AuthStatusPath $apiAuth
    Assert-True (-not $apiBlocked.passed) 'API key presence must be blocked.'
    Assert-True (
        @($apiBlocked.blockers) -contains 'api-billing-environment-detected'
    ) 'API billing blocker must be stable.'

    $paygAuth = Join-Path $tempRoot 'payg-auth.json'
    $paygFixture = Get-Content -Raw $workAuth | ConvertFrom-Json -AsHashtable
    $paygFixture.authMethod = 'apiKey'
    $paygFixture.subscriptionType = $null
    Write-JsonFixture -Path $paygAuth -Value $paygFixture
    $paygBlocked = Invoke-Contract -Action Status -AuthStatusPath $paygAuth
    Assert-True (-not $paygBlocked.passed) 'Pay-as-you-go auth must be blocked.'

    $unknown = Invoke-Contract `
        -Action Prepare `
        -Target unknown `
        -AuthStatusPath $workAuth
    Assert-True (-not $unknown.passed) 'Unknown aliases must fail closed.'
    Assert-True (
        @($unknown.blockers) -contains 'target-profile-not-found'
    ) 'Unknown alias blocker must be stable.'

    $unsafeProfiles = Join-Path $tempRoot 'unsafe-profiles.json'
    Write-JsonFixture -Path $unsafeProfiles -Value @{
        schema_version = 1
        subscription_only = $true
        profiles = @(
            @{
                alias = 'personal'
                aliases = @('personal')
                email = 'personal@example.test'
                token = 'must-not-be-accepted'
            }
        )
    }
    $unsafe = Invoke-Contract `
        -Action Prepare `
        -Target personal `
        -AuthStatusPath $workAuth `
        -Profiles $unsafeProfiles
    Assert-True (-not $unsafe.passed) 'Secret-bearing profiles must fail closed.'
    Assert-True (
        @($unsafe.blockers) -contains 'invalid-profile-config'
    ) 'Unsafe profile config blocker must be stable.'

    Write-Output 'CLAUDE_SWITCH_ACCOUNT_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
