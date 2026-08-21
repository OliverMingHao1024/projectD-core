function Get-ClaudeAccountJsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'JSON file is missing.'
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -gt 65536) {
        throw 'JSON file exceeds the size limit.'
    }
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Test-ClaudeAccountExactProperties {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string[]]$Allowed,
        [Parameter(Mandatory)][string[]]$Required
    )

    $names = @($Value.PSObject.Properties.Name)
    foreach ($name in $names) {
        if ($name -cnotin $Allowed) { return $false }
    }
    foreach ($name in $Required) {
        if ($name -cnotin $names) { return $false }
    }
    return $true
}

function Read-ClaudeAccountProfiles {
    param([Parameter(Mandatory)][string]$Path)

    $config = Get-ClaudeAccountJsonFile $Path
    if (-not (Test-ClaudeAccountExactProperties `
        -Value $config `
        -Allowed @('schema_version', 'subscription_only', 'profiles') `
        -Required @('schema_version', 'subscription_only', 'profiles'))) {
        throw 'Profile root has unexpected fields.'
    }
    if ($config.schema_version -ne 1 -or $config.subscription_only -ne $true) {
        throw 'Profile policy is unsupported.'
    }
    $profiles = @($config.profiles)
    if ($profiles.Count -eq 0) { throw 'No profiles are configured.' }

    $seenAliases = @{}
    $seenEmails = @{}
    foreach ($profile in $profiles) {
        if (-not (Test-ClaudeAccountExactProperties `
            -Value $profile `
            -Allowed @('alias', 'aliases', 'email') `
            -Required @('alias', 'aliases', 'email'))) {
            throw 'A profile has unexpected fields.'
        }
        $alias = ([string]$profile.alias).Trim()
        $email = ([string]$profile.email).Trim().ToLowerInvariant()
        $aliases = @($profile.aliases | ForEach-Object { ([string]$_).Trim() })
        if (-not $alias -or -not $email -or $email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw 'A profile identity is invalid.'
        }
        if ($seenEmails.ContainsKey($email)) { throw 'Profile emails must be unique.' }
        $seenEmails[$email] = $true
        foreach ($candidate in @($alias) + $aliases) {
            if (-not $candidate) { throw 'Profile aliases cannot be empty.' }
            $key = $candidate.ToLowerInvariant()
            if ($seenAliases.ContainsKey($key)) { throw 'Profile aliases must be unique.' }
            $seenAliases[$key] = $true
        }
    }
    return $profiles
}

function Invoke-ClaudeAccountAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Status', 'Prepare', 'Verify')]
        [string]$Action,
        [AllowNull()][object]$Auth,
        [AllowNull()][object]$EnvironmentState,
        [string]$Target,
        [string]$ProfilesPath
    )

    $blockers = [Collections.Generic.List[string]]::new()
    if (-not $Auth) {
        $blockers.Add('auth-status-unavailable')
    } else {
        if (-not [bool]$Auth.loggedIn) { $blockers.Add('not-logged-in') }
        if ($EnvironmentState.apiBilling) {
            $blockers.Add('api-billing-environment-detected')
        }
        if ($EnvironmentState.thirdParty) {
            $blockers.Add('third-party-provider-environment-detected')
        }
        if (-not [string]::Equals(
            [string]$Auth.authMethod,
            'claude.ai',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            $blockers.Add('not-claude-subscription-auth')
        }
        if (-not [string]::Equals(
            [string]$Auth.apiProvider,
            'firstParty',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            $blockers.Add('not-first-party-provider')
        }
        if ([string]::IsNullOrWhiteSpace([string]$Auth.subscriptionType)) {
            $blockers.Add('subscription-not-detected')
        }
    }

    $targetProfile = $null
    if ($Action -in @('Prepare', 'Verify')) {
        if (-not $Target -or -not $ProfilesPath) {
            $blockers.Add('target-and-profiles-required')
        } else {
            try {
                $profiles = @(Read-ClaudeAccountProfiles $ProfilesPath)
                $normalizedTarget = $Target.Trim().ToLowerInvariant()
                $matches = @($profiles | Where-Object {
                    $names = @([string]$_.alias) + @(
                        $_.aliases | ForEach-Object { [string]$_ }
                    )
                    @($names | Where-Object {
                        $_.Trim().ToLowerInvariant() -eq $normalizedTarget
                    }).Count -gt 0
                })
                if ($matches.Count -eq 1) {
                    $targetProfile = $matches[0]
                } else {
                    $blockers.Add('target-profile-not-found')
                }
            } catch {
                $blockers.Add('invalid-profile-config')
            }
        }
    }

    $alreadyActive = $false
    if ($Auth -and $targetProfile) {
        $alreadyActive = [string]::Equals(
            ([string]$Auth.email).Trim(),
            ([string]$targetProfile.email).Trim(),
            [StringComparison]::OrdinalIgnoreCase
        )
    }
    if ($Action -eq 'Verify' -and $targetProfile -and -not $alreadyActive) {
        $blockers.Add('active-account-does-not-match-target')
    }

    $passed = $blockers.Count -eq 0
    [pscustomobject][ordered]@{
        passed = $passed
        action = $Action.ToLowerInvariant()
        current = if ($Auth) {
            [ordered]@{
                email = [string]$Auth.email
                org_name = [string]$Auth.orgName
                subscription_type = [string]$Auth.subscriptionType
                auth_method = [string]$Auth.authMethod
                api_provider = [string]$Auth.apiProvider
            }
        } else { $null }
        target = if ($targetProfile) {
            [ordered]@{
                alias = [string]$targetProfile.alias
                email = [string]$targetProfile.email
            }
        } else { $null }
        already_active = $alreadyActive
        ready_to_switch = (
            $Action -eq 'Prepare' -and $passed -and -not $alreadyActive
        )
        blockers = @($blockers)
    }
}
