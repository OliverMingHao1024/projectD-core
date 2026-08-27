[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $core 'scripts\lib\UsageContract.psm1'
$accountSchemaPath = Join-Path $core (
    'evals\schemas\usage-account-profiles.schema.json'
)
$deviceSchemaPath = Join-Path $core (
    'evals\schemas\usage-device-profile.schema.json'
)
$eventSchemaPath = Join-Path $core 'evals\schemas\usage-events.schema.json'
$claudeStatusPath = Join-Path $core 'scripts\claude-account.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "usage-contract-$PID"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )
    $thrown = $false
    try { $null = & $Action } catch { $thrown = $true }
    Assert-True $thrown $Message
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    $Value | ConvertTo-Json -Depth 20 | Set-Content `
        -LiteralPath $Path -Encoding utf8 -NoNewline
}

function Assert-ConformsToSchema {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$Message
    )
    $json = $Value | ConvertTo-Json -Depth 20
    Assert-True (
        Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop
    ) $Message
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Import-Module $modulePath -Force

    $accountsPath = Join-Path $tempRoot 'usage-account-profiles.json'
    $workDevicePath = Join-Path $tempRoot 'usage-device-work.json'
    $homeDevicePath = Join-Path $tempRoot 'usage-device-home.json'
    $unsafeAccountsPath = Join-Path $tempRoot 'unsafe-accounts.json'

    $accountsFixture = [ordered]@{
        schema_version = 1
        accounts = @(
            [ordered]@{
                provider = 'codex'
                account_id = 'acct_11111111111111111111111111111111'
                alias = 'personal-codex'
                aliases = @('codex-personal')
                email = 'codex@example.test'
            }
            [ordered]@{
                provider = 'claude'
                account_id = 'acct_22222222222222222222222222222222'
                alias = 'work-claude'
                aliases = @('claude-work')
                email = 'claude@example.test'
            }
            [ordered]@{
                provider = 'claude'
                account_id = 'acct_33333333333333333333333333333333'
                alias = 'personal-claude'
                aliases = @('claude-personal')
                email = 'personal@example.test'
            }
        )
    }
    $workDeviceFixture = [ordered]@{
        schema_version = 1
        device_id = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        environment = 'work'
    }
    $homeDeviceFixture = [ordered]@{
        schema_version = 1
        device_id = 'dev_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        environment = 'home'
    }
    Write-JsonFixture -Path $accountsPath -Value $accountsFixture
    Write-JsonFixture -Path $workDevicePath -Value $workDeviceFixture
    Write-JsonFixture -Path $homeDevicePath -Value $homeDeviceFixture

    Assert-ConformsToSchema $accountsFixture $accountSchemaPath (
        'The local account profile fixture must conform to its schema.'
    )
    Assert-ConformsToSchema $workDeviceFixture $deviceSchemaPath (
        'The local device fixture must conform to its schema.'
    )

    $profiles = Read-ProjectDUsageAccountProfiles -Path $accountsPath
    $workDevice = Read-ProjectDUsageDeviceProfile -Path $workDevicePath
    $homeDevice = Read-ProjectDUsageDeviceProfile -Path $homeDevicePath

    $codexObservation = ConvertTo-ProjectDCodexAccountObservation -AccountRead (
        [pscustomobject]@{
            account = [pscustomobject]@{
                type = 'chatgpt'
                email = 'codex@example.test'
                planType = 'pro'
            }
            requiresOpenaiAuth = $true
        }
    )
    $codexWorkIdentity = Resolve-ProjectDUsageIdentity `
        -Observation $codexObservation `
        -AccountProfiles $profiles `
        -DeviceProfile $workDevice `
        -CapturedAt '2026-08-28T00:00:00Z'
    $codexHomeIdentity = Resolve-ProjectDUsageIdentity `
        -Observation $codexObservation `
        -AccountProfiles $profiles `
        -DeviceProfile $homeDevice `
        -CapturedAt '2026-08-28T00:00:01Z'

    Assert-True (
        $codexWorkIdentity.verification_status -ceq 'verified'
    ) 'A mapped Codex ChatGPT account must verify.'
    Assert-True (
        $codexWorkIdentity.billing_source -ceq 'subscription'
    ) 'Codex ChatGPT auth must be classified as subscription billing.'
    Assert-True (
        $codexWorkIdentity.account_id -ceq $codexHomeIdentity.account_id
    ) 'The same account profile must keep one account_id across devices.'
    Assert-True (
        $codexWorkIdentity.device_id -cne $codexHomeIdentity.device_id
    ) 'Work and home devices must retain different device_id values.'
    $codexIdentityJson = $codexWorkIdentity | ConvertTo-Json -Depth 10
    Assert-True (
        $codexIdentityJson -notmatch '(?i)email|org|token|secret|credential'
    ) 'Verified identity snapshots must not expose identity source or secrets.'

    $claudeObservation = ConvertTo-ProjectDClaudeAccountObservation `
        -Auth ([pscustomobject]@{
            loggedIn = $true
            authMethod = 'claude.ai'
            apiProvider = 'firstParty'
            subscriptionType = 'team'
            email = 'claude@example.test'
            orgName = 'Example Org'
        }) `
        -EnvironmentState ([pscustomobject]@{
            apiBilling = $false
            thirdParty = $false
        })
    $claudeIdentity = Resolve-ProjectDUsageIdentity `
        -Observation $claudeObservation `
        -AccountProfiles $profiles `
        -DeviceProfile $workDevice `
        -CapturedAt '2026-08-28T00:00:02Z'
    Assert-True (
        $claudeIdentity.verification_status -ceq 'verified'
    ) 'A mapped Claude subscription account must verify.'
    Assert-True (
        $claudeIdentity.billing_source -ceq 'subscription'
    ) 'Claude first-party subscription auth must be classified as subscription.'
    Assert-True (
        ($claudeIdentity | ConvertTo-Json -Depth 10) -notmatch '(?i)email|org'
    ) 'Claude identity snapshots must not expose email or organization.'

    $codexApiObservation = ConvertTo-ProjectDCodexAccountObservation -AccountRead (
        [pscustomobject]@{
            account = [pscustomobject]@{ type = 'apiKey' }
            requiresOpenaiAuth = $true
        }
    )
    $codexApiIdentity = Resolve-ProjectDUsageIdentity `
        -Observation $codexApiObservation `
        -AccountProfiles $profiles `
        -DeviceProfile $workDevice `
        -CapturedAt '2026-08-28T00:00:03Z'
    Assert-True (
        $codexApiIdentity.billing_source -ceq 'api-key'
    ) 'Codex API key auth must remain distinct from subscriptions.'
    Assert-True (
        $codexApiIdentity.verification_status -ceq 'unknown' -and
        $null -eq $codexApiIdentity.account_id
    ) 'Identity without a verified account email must fail closed.'

    $codexCloudObservation = ConvertTo-ProjectDCodexAccountObservation -AccountRead (
        [pscustomobject]@{
            account = [pscustomobject]@{
                type = 'amazonBedrock'
                credentialSource = 'awsManaged'
            }
            requiresOpenaiAuth = $false
        }
    )
    Assert-True (
        $codexCloudObservation.billing_source -ceq 'third-party-cloud'
    ) 'Codex Bedrock auth must remain distinct from API key billing.'

    $claudeApiObservation = ConvertTo-ProjectDClaudeAccountObservation `
        -Auth ([pscustomobject]@{
            loggedIn = $true
            authMethod = 'apiKey'
            apiProvider = 'firstParty'
            subscriptionType = $null
            email = 'claude@example.test'
        }) `
        -EnvironmentState ([pscustomobject]@{
            apiBilling = $true
            thirdParty = $false
        })
    Assert-True (
        $claudeApiObservation.billing_source -ceq 'api-key'
    ) 'Claude API billing must remain distinct from subscriptions.'

    $claudeCloudObservation = ConvertTo-ProjectDClaudeAccountObservation `
        -Auth ([pscustomobject]@{
            loggedIn = $true
            authMethod = 'apiKey'
            apiProvider = 'bedrock'
            subscriptionType = $null
            email = 'claude@example.test'
        }) `
        -EnvironmentState ([pscustomobject]@{
            apiBilling = $true
            thirdParty = $true
        })
    Assert-True (
        $claudeCloudObservation.billing_source -ceq 'third-party-cloud'
    ) 'Claude third-party routing must remain distinct from direct API billing.'

    $unknownObservation = [pscustomobject][ordered]@{
        provider = 'codex'
        observation_status = 'unidentified'
        observed_email = $null
        billing_source = 'unavailable'
        plan_type = $null
    }
    $unknownIdentity = Resolve-ProjectDUsageIdentity `
        -Observation $unknownObservation `
        -AccountProfiles $profiles `
        -DeviceProfile $workDevice `
        -ExpectedAccountId $codexWorkIdentity.account_id `
        -CapturedAt '2026-08-28T00:00:04Z'
    Assert-True (
        $unknownIdentity.verification_status -ceq 'unknown' -and
        $null -eq $unknownIdentity.account_id -and
        $null -eq $unknownIdentity.account_alias
    ) 'Unknown identity must never inherit the previously verified account.'

    $personalObservation = ConvertTo-ProjectDClaudeAccountObservation `
        -Auth ([pscustomobject]@{
            loggedIn = $true
            authMethod = 'claude.ai'
            apiProvider = 'firstParty'
            subscriptionType = 'pro'
            email = 'personal@example.test'
        }) `
        -EnvironmentState ([pscustomobject]@{
            apiBilling = $false
            thirdParty = $false
        })
    $mismatchIdentity = Resolve-ProjectDUsageIdentity `
        -Observation $personalObservation `
        -AccountProfiles $profiles `
        -DeviceProfile $workDevice `
        -ExpectedAccountId $claudeIdentity.account_id `
        -CapturedAt '2026-08-28T00:00:05Z'
    Assert-True (
        $mismatchIdentity.verification_status -ceq 'mismatch' -and
        $null -eq $mismatchIdentity.account_id -and
        $null -eq $mismatchIdentity.account_alias
    ) 'A changed account must fail closed instead of inheriting prior identity.'

    $codexEvent = New-ProjectDUsageEvent `
        -EventId 'evt-codex-1' `
        -SourceEventId 'turn-1' `
        -SessionId 'thread-codex-1' `
        -TurnId 'turn-codex-1' `
        -OccurredAt '2026-08-28T00:01:00Z' `
        -Identity $codexWorkIdentity `
        -Model 'gpt-5.6' `
        -Metrics ([ordered]@{
            input_tokens = 100
            cached_input_tokens = 80
            output_tokens = 20
            reasoning_tokens = 5
        })
    Assert-ConformsToSchema $codexEvent $eventSchemaPath (
        'A normalized Codex usage event must conform to the shared schema.'
    )
    Assert-True (
        $codexEvent.usage.cache_creation_tokens.status -ceq 'unavailable' -and
        $null -eq $codexEvent.usage.cache_creation_tokens.value
    ) 'Missing provider-specific metrics must be unavailable, not zero.'
    Assert-True (
        ($codexEvent | ConvertTo-Json -Depth 20) -notmatch '(?i)prompt|response|tool_arguments|tool_output|email'
    ) 'Usage events must remain metadata-only and de-identified.'

    $claudeEvent = New-ProjectDUsageEvent `
        -EventId 'evt-claude-1' `
        -SourceEventId 'turn-2' `
        -SessionId 'session-claude-1' `
        -TurnId 'turn-claude-1' `
        -OccurredAt '2026-08-28T00:02:00Z' `
        -Identity $claudeIdentity `
        -Model 'claude-opus-example' `
        -Metrics ([ordered]@{
            input_tokens = 120
            cached_input_tokens = 60
            output_tokens = 30
            cache_creation_tokens = 15
            estimated_cost_usd = 0.25
        })
    Assert-ConformsToSchema $claudeEvent $eventSchemaPath (
        'A normalized Claude usage event must conform to the shared schema.'
    )
    Assert-True (
        $claudeEvent.usage.reasoning_tokens.status -ceq 'unavailable'
    ) 'Unsupported Claude reasoning tokens must be explicitly unavailable.'
    Assert-Throws {
        New-ProjectDUsageEvent `
            -EventId 'evt-unsafe' `
            -SourceEventId 'turn-unsafe' `
            -SessionId 'session-unsafe' `
            -TurnId 'turn-unsafe' `
            -OccurredAt '2026-08-28T00:03:00Z' `
            -Identity $claudeIdentity `
            -Metrics @{ prompt = 'must-not-be-accepted' }
    } 'Unknown or content-bearing usage fields must be rejected.'
    Assert-Throws {
        New-ProjectDUsageEvent `
            -EventId 'evt-missing-timezone' `
            -SourceEventId 'turn-missing-timezone' `
            -SessionId 'session-missing-timezone' `
            -TurnId 'turn-missing-timezone' `
            -OccurredAt '2026-08-28T00:03:00' `
            -Identity $claudeIdentity
    } 'Usage timestamps without an explicit timezone must be rejected.'
    Assert-Throws {
        New-ProjectDUsageEvent `
            -EventId 'evt-long-model' `
            -SourceEventId 'turn-long-model' `
            -SessionId 'session-long-model' `
            -TurnId 'turn-long-model' `
            -OccurredAt '2026-08-28T00:03:00Z' `
            -Identity $claudeIdentity `
            -Model ('m' * 129)
    } 'The event builder must not produce values rejected by its schema.'
    Assert-Throws {
        New-ProjectDUsageEvent `
            -EventId 'evt-content-model' `
            -SourceEventId 'turn-content-model' `
            -SessionId 'session-content-model' `
            -TurnId 'turn-content-model' `
            -OccurredAt '2026-08-28T00:03:00Z' `
            -Identity $claudeIdentity `
            -Model 'user@example.test'
    } 'Model metadata must reject content-like values.'
    $providerMismatch = $codexEvent | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json
    $providerMismatch.provider = 'claude'
    Assert-Throws {
        Assert-ConformsToSchema $providerMismatch $eventSchemaPath (
            'Outer and identity providers must match.'
        )
    } 'The shared schema must reject mismatched provider identities.'

    $accountIdOne = New-ProjectDUsageIdentifier -Kind Account
    $accountIdTwo = New-ProjectDUsageIdentifier -Kind Account
    $deviceId = New-ProjectDUsageIdentifier -Kind Device
    Assert-True (
        $accountIdOne -cmatch '^acct_[a-f0-9]{32}$' -and
        $accountIdOne -cne $accountIdTwo
    ) 'Account identifiers must be random, prefixed, and unique.'
    Assert-True (
        $deviceId -cmatch '^dev_[a-f0-9]{32}$'
    ) 'Device identifiers must be random and separately namespaced.'

    $unsafeAccounts = $accountsFixture | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $unsafeAccounts.accounts[0].token = 'must-not-be-accepted'
    Write-JsonFixture -Path $unsafeAccountsPath -Value $unsafeAccounts
    $unsafeProfileError = $null
    try {
        Read-ProjectDUsageAccountProfiles -Path $unsafeAccountsPath
    } catch {
        $unsafeProfileError = $_.Exception.Message
    }
    Assert-True (
        -not [string]::IsNullOrWhiteSpace($unsafeProfileError)
    ) 'Secret-bearing or unknown account profile fields must fail closed.'
    Assert-True (
        $unsafeProfileError -notmatch 'must-not-be-accepted|codex@example\.test'
    ) 'Profile validation errors must not echo local email or rejected values.'
    $invalidAliases = $accountsFixture | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json -AsHashtable
    $invalidAliases.accounts[0].aliases = $null
    $invalidAliasesPath = Join-Path $tempRoot 'invalid-aliases.json'
    Write-JsonFixture -Path $invalidAliasesPath -Value $invalidAliases
    Assert-Throws {
        Read-ProjectDUsageAccountProfiles -Path $invalidAliasesPath
    } 'The profile reader must enforce the canonical JSON Schema.'
    $invalidDevice = [pscustomobject][ordered]@{
        schema_version = 1
        device_id = 'dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        environment = 'work'
        email = 'must-not-be-accepted@example.test'
    }
    Assert-Throws {
        Resolve-ProjectDUsageIdentity `
            -Observation $codexObservation `
            -AccountProfiles $profiles `
            -DeviceProfile $invalidDevice `
            -CapturedAt '2026-08-28T00:00:00Z'
    } 'Identity resolution must reject device objects outside the schema.'

    Assert-True (
        Test-Path -LiteralPath $claudeStatusPath -PathType Leaf
    ) 'The documented scripts/claude-account.ps1 entrypoint must exist.'
    $savedAnthropicApiKey = $env:ANTHROPIC_API_KEY
    $savedAnthropicAuthToken = $env:ANTHROPIC_AUTH_TOKEN
    $savedClaudeOauthToken = $env:CLAUDE_CODE_OAUTH_TOKEN
    $savedBedrock = $env:CLAUDE_CODE_USE_BEDROCK
    $savedVertex = $env:CLAUDE_CODE_USE_VERTEX
    $savedFoundry = $env:CLAUDE_CODE_USE_FOUNDRY
    try {
        $env:ANTHROPIC_API_KEY = $null
        $env:ANTHROPIC_AUTH_TOKEN = $null
        $env:CLAUDE_CODE_OAUTH_TOKEN = $null
        $env:CLAUDE_CODE_USE_BEDROCK = $null
        $env:CLAUDE_CODE_USE_VERTEX = $null
        $env:CLAUDE_CODE_USE_FOUNDRY = $null
        function global:claude {
            $global:LASTEXITCODE = 0
            [ordered]@{
                loggedIn = $true
                authMethod = 'claude.ai'
                apiProvider = 'firstParty'
                subscriptionType = 'team'
                email = 'status@example.test'
                orgName = 'Example Org'
            } | ConvertTo-Json -Compress
        }
        $statusOutput = @(& $claudeStatusPath -Action Status) -join "`n"
        $statusResult = $statusOutput | ConvertFrom-Json
        Assert-True (
            [bool]$statusResult.passed -and
            [string]$statusResult.action -ceq 'status'
        ) 'The public Claude Status entrypoint must execute successfully.'
    } finally {
        Remove-Item Function:\global:claude -ErrorAction SilentlyContinue
        $env:ANTHROPIC_API_KEY = $savedAnthropicApiKey
        $env:ANTHROPIC_AUTH_TOKEN = $savedAnthropicAuthToken
        $env:CLAUDE_CODE_OAUTH_TOKEN = $savedClaudeOauthToken
        $env:CLAUDE_CODE_USE_BEDROCK = $savedBedrock
        $env:CLAUDE_CODE_USE_VERTEX = $savedVertex
        $env:CLAUDE_CODE_USE_FOUNDRY = $savedFoundry
    }

    Write-Output 'USAGE_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
