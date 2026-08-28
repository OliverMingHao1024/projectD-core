Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'GovernanceCommon.psm1') -Force

function Test-UsageExactProperties {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string[]]$Allowed,
        [Parameter(Mandatory)][string[]]$Required
    )

    if ($null -eq $Value) { return $false }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($name in $names) {
        if ($name -cnotin $Allowed) { return $false }
    }
    foreach ($name in $Required) {
        if ($name -cnotin $names) { return $false }
    }
    return $true
}

function Get-UsageJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$MaximumBytes
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Usage contract JSON file is missing.'
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt $MaximumBytes) {
        throw 'Usage contract JSON file exceeds the size limit.'
    }
    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    } catch {
        throw "Usage contract JSON is invalid: $($_.Exception.Message)"
    }
}

function Get-UsageSchemaPath {
    param([Parameter(Mandatory)][string]$FileName)

    $path = [IO.Path]::GetFullPath((
        Join-Path $PSScriptRoot "..\..\evals\schemas\$FileName"
    ))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Canonical usage schema is missing: $FileName"
    }
    return $path
}

function Assert-UsageSchemaValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaFileName,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        $json = $Value | ConvertTo-Json -Depth 32
        $valid = Test-Json `
            -Json $json `
            -SchemaFile (Get-UsageSchemaPath -FileName $SchemaFileName) `
            -ErrorAction Stop
        if (-not $valid) { throw 'JSON Schema validation returned false.' }
    } catch {
        throw "$Label does not conform to its canonical schema."
    }
}

function ConvertTo-UsageUtcTimestamp {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Value -cnotmatch '(?:Z|[+-]\d{2}:\d{2})$') {
        throw "$Label must include an explicit UTC offset or Z suffix."
    }
    try {
        return [DateTimeOffset]::Parse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
    } catch {
        throw "$Label must be an ISO 8601 timestamp."
    }
}

function Test-UsageAccountId {
    param([AllowNull()][object]$Value)
    return [string]$Value -cmatch '^acct_[a-f0-9]{32}$'
}

function Test-UsageDeviceId {
    param([AllowNull()][object]$Value)
    return [string]$Value -cmatch '^dev_[a-f0-9]{32}$'
}

function Test-UsageAlias {
    param([AllowNull()][object]$Value)
    return [string]$Value -cmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$'
}

function Test-UsageEmail {
    param([AllowNull()][object]$Value)
    return [string]$Value -cmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$'
}

function Assert-UsageAccountProfilesValue {
    param([Parameter(Mandatory)]$Config)

    Assert-UsageSchemaValue `
        -Value $Config `
        -SchemaFileName 'usage-account-profiles.schema.json' `
        -Label 'Usage account profile'
    $accounts = @($Config.accounts)
    $seenAccountIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $seenEmails = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $seenAliases = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($account in $accounts) {
        $provider = ([string]$account.provider).Trim().ToLowerInvariant()
        $accountId = ([string]$account.account_id).Trim()
        $email = ([string]$account.email).Trim().ToLowerInvariant()
        $aliases = @([string]$account.alias) + @(
            $account.aliases | ForEach-Object { [string]$_ }
        )
        if (-not $seenAccountIds.Add("$provider`:$accountId")) {
            throw 'Usage account_id values must be unique per provider.'
        }
        if (-not $seenEmails.Add("$provider`:$email")) {
            throw 'Usage account emails must be unique per provider.'
        }
        foreach ($alias in $aliases) {
            if (-not $seenAliases.Add("$provider`:$alias")) {
                throw 'Usage account aliases must be unique per provider.'
            }
        }
    }
}

function Assert-UsageDeviceProfileValue {
    param([Parameter(Mandatory)]$Config)

    Assert-UsageSchemaValue `
        -Value $Config `
        -SchemaFileName 'usage-device-profile.schema.json' `
        -Label 'Usage device profile'
}

function New-ProjectDUsageIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Account', 'Device')]
        [string]$Kind
    )

    $prefix = if ($Kind -ceq 'Account') { 'acct_' } else { 'dev_' }
    return $prefix + [Guid]::NewGuid().ToString('N')
}

function Read-ProjectDUsageAccountProfiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Get-UsageJsonFile -Path $Path -MaximumBytes 64KB
    Assert-UsageAccountProfilesValue -Config $config
    return $config
}

function Read-ProjectDUsageDeviceProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Get-UsageJsonFile -Path $Path -MaximumBytes 4KB
    Assert-UsageDeviceProfileValue -Config $config
    return $config
}

function ConvertTo-ProjectDCodexAccountObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$AccountRead)

    $payload = if (
        $AccountRead.PSObject.Properties.Name -ccontains 'result'
    ) { $AccountRead.result } else { $AccountRead }
    $account = if (
        $null -ne $payload -and
        $payload.PSObject.Properties.Name -ccontains 'account'
    ) { $payload.account } else { $null }
    $accountType = if ($null -eq $account) {
        ''
    } else { ([string]$account.type).Trim() }
    $email = $null
    $billingSource = 'unavailable'
    $planType = $null
    $observationStatus = 'unidentified'

    switch -CaseSensitive ($accountType) {
        'chatgpt' {
            $billingSource = 'subscription'
            $email = ([string]$account.email).Trim().ToLowerInvariant()
            $planType = ([string]$account.planType).Trim()
            if (Test-UsageEmail $email) { $observationStatus = 'identified' }
        }
        'apiKey' {
            $billingSource = 'api-key'
        }
        'amazonBedrock' {
            $billingSource = 'third-party-cloud'
        }
    }

    return [pscustomobject][ordered]@{
        provider = 'codex'
        observation_status = $observationStatus
        observed_email = if ($observationStatus -ceq 'identified') {
            $email
        } else { $null }
        billing_source = $billingSource
        plan_type = if ([string]::IsNullOrWhiteSpace($planType)) {
            $null
        } else { $planType }
    }
}

function ConvertTo-ProjectDClaudeAccountObservation {
    [CmdletBinding()]
    param(
        [AllowNull()]$Auth,
        [AllowNull()]$EnvironmentState
    )

    $thirdParty = (
        $null -ne $EnvironmentState -and
        [bool]$EnvironmentState.thirdParty
    )
    $apiBilling = (
        $null -ne $EnvironmentState -and
        [bool]$EnvironmentState.apiBilling
    )
    $subscription = (
        $null -ne $Auth -and
        [bool]$Auth.loggedIn -and
        [string]::Equals(
            [string]$Auth.authMethod,
            'claude.ai',
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [string]::Equals(
            [string]$Auth.apiProvider,
            'firstParty',
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        -not [string]::IsNullOrWhiteSpace([string]$Auth.subscriptionType)
    )
    $billingSource = if ($thirdParty) {
        'third-party-cloud'
    } elseif ($apiBilling -or (
        $null -ne $Auth -and
        [string]::Equals(
            [string]$Auth.authMethod,
            'apiKey',
            [StringComparison]::OrdinalIgnoreCase
        )
    )) {
        'api-key'
    } elseif ($subscription) {
        'subscription'
    } else { 'unavailable' }

    $email = if ($subscription) {
        ([string]$Auth.email).Trim().ToLowerInvariant()
    } else { $null }
    $identified = $subscription -and (Test-UsageEmail $email)
    $planType = if ($subscription) {
        ([string]$Auth.subscriptionType).Trim()
    } else { $null }

    return [pscustomobject][ordered]@{
        provider = 'claude'
        observation_status = if ($identified) { 'identified' } else { 'unidentified' }
        observed_email = if ($identified) { $email } else { $null }
        billing_source = $billingSource
        plan_type = if ([string]::IsNullOrWhiteSpace($planType)) {
            $null
        } else { $planType }
    }
}

function Resolve-ProjectDUsageIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Observation,
        [Parameter(Mandatory)]$AccountProfiles,
        [Parameter(Mandatory)]$DeviceProfile,
        [string]$ExpectedAccountId,
        [Parameter(Mandatory)][string]$CapturedAt
    )

    Assert-UsageAccountProfilesValue -Config $AccountProfiles
    Assert-UsageDeviceProfileValue -Config $DeviceProfile
    if (-not (Test-UsageExactProperties `
        -Value $Observation `
        -Allowed @(
            'provider',
            'observation_status',
            'observed_email',
            'billing_source',
            'plan_type'
        ) `
        -Required @(
            'provider',
            'observation_status',
            'observed_email',
            'billing_source',
            'plan_type'
        ))) {
        throw 'Usage account observation has unexpected fields.'
    }
    $provider = ([string]$Observation.provider).Trim().ToLowerInvariant()
    if ($provider -cnotin @('codex', 'claude')) {
        throw 'Usage observation provider is unsupported.'
    }
    if ([string]$Observation.observation_status -cnotin @(
        'identified', 'unidentified'
    )) {
        throw 'Usage observation status is unsupported.'
    }
    if ([string]$Observation.billing_source -cnotin @(
        'subscription', 'api-key', 'third-party-cloud', 'unavailable'
    )) {
        throw 'Usage billing source is unsupported.'
    }
    if (-not (Test-UsageDeviceId $DeviceProfile.device_id)) {
        throw 'Usage device profile is invalid.'
    }
    if ([string]$DeviceProfile.environment -cnotin @('work', 'home', 'other')) {
        throw 'Usage device environment is unsupported.'
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ExpectedAccountId) -and
        -not (Test-UsageAccountId $ExpectedAccountId)
    ) {
        throw 'ExpectedAccountId is invalid.'
    }
    $captured = ConvertTo-UsageUtcTimestamp -Value $CapturedAt -Label 'CapturedAt'

    $matched = $null
    if (
        [string]$Observation.observation_status -ceq 'identified' -and
        (Test-UsageEmail $Observation.observed_email)
    ) {
        $matches = @($AccountProfiles.accounts | Where-Object {
            [string]$_.provider -ceq $provider -and
            [string]::Equals(
                ([string]$_.email).Trim(),
                ([string]$Observation.observed_email).Trim(),
                [StringComparison]::OrdinalIgnoreCase
            )
        })
        if ($matches.Count -eq 1) { $matched = $matches[0] }
    }

    $verificationStatus = 'unknown'
    $accountId = $null
    $accountAlias = $null
    if ($null -ne $matched) {
        if (
            -not [string]::IsNullOrWhiteSpace($ExpectedAccountId) -and
            [string]$matched.account_id -cne $ExpectedAccountId
        ) {
            $verificationStatus = 'mismatch'
        } else {
            $verificationStatus = 'verified'
            $accountId = [string]$matched.account_id
            $accountAlias = [string]$matched.alias
        }
    }

    $planType = ([string]$Observation.plan_type).Trim()
    return [pscustomobject][ordered]@{
        schema_version = 1
        captured_at = $captured.ToString('o')
        provider = $provider
        verification_status = $verificationStatus
        account_id = $accountId
        account_alias = $accountAlias
        device_id = [string]$DeviceProfile.device_id
        environment = [string]$DeviceProfile.environment
        billing_source = [string]$Observation.billing_source
        plan_type = [pscustomobject][ordered]@{
            status = if ([string]::IsNullOrWhiteSpace($planType)) {
                'unavailable'
            } else { 'observed' }
            value = if ([string]::IsNullOrWhiteSpace($planType)) {
                $null
            } else { $planType }
        }
    }
}

function Write-ProjectDUsageIdentityDiagnostic {
    <#
    Called after Resolve-ProjectDUsageIdentity whenever the caller is
    about to fail closed on a non-verified identity. Persists a
    non-identifying record (no email, account_id, or alias -- those
    are already forced to null for unknown/mismatch identities) so a
    later report (#43) can surface unknown-identity and
    account-mismatch counts without the caller needing its own
    logging path. A verified identity is a silent no-op.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$Path
    )

    if ([string]$Identity.verification_status -ceq 'verified') {
        return $null
    }
    if ([string]$Identity.verification_status -cnotin @('unknown', 'mismatch')) {
        throw 'Identity has an unsupported verification_status.'
    }
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $root '.local\usage\diagnostics\identity-events.jsonl'
    }
    $resolved = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $Path))
    }
    $localRoot = [IO.Path]::GetFullPath((Join-Path $root '.local'))
    if (-not $resolved.StartsWith(
        $localRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Identity diagnostic path must stay inside ProjectRoot/.local.'
    }
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $resolved
    ) -Force | Out-Null
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $resolved) {
        throw 'Identity diagnostic path must not cross a reparse point.'
    }
    $record = [pscustomobject][ordered]@{
        schema_version = 1
        occurred_at = ([DateTimeOffset]$Identity.captured_at).ToUniversalTime().ToString('o')
        provider = [string]$Identity.provider
        verification_status = [string]$Identity.verification_status
        device_id = [string]$Identity.device_id
        environment = [string]$Identity.environment
    }
    $schemaPath = Join-Path $PSScriptRoot (
        '..\..\evals\schemas\usage-identity-diagnostic.schema.json'
    )
    $json = $record | ConvertTo-Json -Depth 8
    if (-not (Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop)) {
        throw 'Identity diagnostic does not conform to its canonical schema.'
    }
    $lockPath = "$resolved.lock"
    $lock = $null
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $lock = [IO.FileStream]::new(
                $lockPath, [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite, [IO.FileShare]::None
            )
        } catch [IO.IOException] {
            if ($stopwatch.Elapsed -ge [TimeSpan]::FromSeconds(10)) {
                throw 'Timed out waiting for the identity diagnostic writer.'
            }
            Start-Sleep -Milliseconds 50
        }
    } while ($null -eq $lock)
    try {
        $line = ($record | ConvertTo-Json -Depth 8 -Compress) + "`n"
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($line)
        $stream = [IO.FileStream]::new(
            $resolved, [IO.FileMode]::Append,
            [IO.FileAccess]::Write, [IO.FileShare]::Read
        )
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    } finally {
        $lock.Dispose()
    }
    return $resolved
}

function New-UsageMetricValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    if ($null -eq $Value) {
        return [pscustomobject][ordered]@{
            status = 'unavailable'
            value = $null
        }
    }
    if (
        $Value -is [bool] -or
        $Value -is [string] -or
        $Value -isnot [ValueType]
    ) {
        throw "$Name must be numeric or null."
    }
    try { $number = [decimal]$Value } catch {
        throw "$Name must be numeric or null."
    }
    if ($number -lt 0) { throw "$Name cannot be negative." }
    if ($Name -ne 'estimated_cost_usd' -and ($number % 1) -ne 0) {
        throw "$Name must be an integer."
    }
    return [pscustomobject][ordered]@{
        status = 'observed'
        value = if ($Name -eq 'estimated_cost_usd') {
            $number
        } else { [long]$number }
    }
}

function Test-UsageIdentitySnapshot {
    param([Parameter(Mandatory)]$Identity)

    if (-not (Test-UsageExactProperties `
        -Value $Identity `
        -Allowed @(
            'schema_version',
            'captured_at',
            'provider',
            'verification_status',
            'account_id',
            'account_alias',
            'device_id',
            'environment',
            'billing_source',
            'plan_type'
        ) `
        -Required @(
            'schema_version',
            'captured_at',
            'provider',
            'verification_status',
            'account_id',
            'account_alias',
            'device_id',
            'environment',
            'billing_source',
            'plan_type'
        ))) {
        return $false
    }
    if ([int]$Identity.schema_version -ne 1) { return $false }
    if ([string]$Identity.provider -cnotin @('codex', 'claude')) { return $false }
    if ([string]$Identity.verification_status -cnotin @(
        'verified', 'unknown', 'mismatch'
    )) { return $false }
    if (-not (Test-UsageDeviceId $Identity.device_id)) { return $false }
    if ([string]$Identity.environment -cnotin @('work', 'home', 'other')) {
        return $false
    }
    if ([string]$Identity.billing_source -cnotin @(
        'subscription', 'api-key', 'third-party-cloud', 'unavailable'
    )) { return $false }
    if ([string]$Identity.verification_status -ceq 'verified') {
        if (
            -not (Test-UsageAccountId $Identity.account_id) -or
            -not (Test-UsageAlias $Identity.account_alias)
        ) { return $false }
    } elseif (
        $null -ne $Identity.account_id -or
        $null -ne $Identity.account_alias
    ) { return $false }
    if (-not (Test-UsageExactProperties `
        -Value $Identity.plan_type `
        -Allowed @('status', 'value') `
        -Required @('status', 'value'))) {
        return $false
    }
    if ([string]$Identity.plan_type.status -ceq 'observed') {
        if ([string]::IsNullOrWhiteSpace([string]$Identity.plan_type.value)) {
            return $false
        }
    } elseif (
        [string]$Identity.plan_type.status -cne 'unavailable' -or
        $null -ne $Identity.plan_type.value
    ) { return $false }
    return $true
}

function New-ProjectDUsageEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EventId,
        [Parameter(Mandatory)][string]$SourceEventId,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$TurnId,
        [Parameter(Mandatory)][string]$OccurredAt,
        [Parameter(Mandatory)]$Identity,
        [string]$Model,
        [Collections.IDictionary]$Metrics = @{}
    )

    $idPattern = '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
    if ($EventId -cnotmatch $idPattern) { throw 'EventId is invalid.' }
    if ($SourceEventId -cnotmatch $idPattern) { throw 'SourceEventId is invalid.' }
    if ($SessionId -cnotmatch $idPattern) { throw 'SessionId is invalid.' }
    if ($TurnId -cnotmatch $idPattern) { throw 'TurnId is invalid.' }
    if (-not (Test-UsageIdentitySnapshot $Identity)) {
        throw 'Identity does not conform to the usage identity contract.'
    }
    $occurred = ConvertTo-UsageUtcTimestamp -Value $OccurredAt -Label 'OccurredAt'

    $metricNames = @(
        'input_tokens',
        'cached_input_tokens',
        'output_tokens',
        'reasoning_tokens',
        'cache_creation_tokens',
        'estimated_cost_usd'
    )
    foreach ($name in @($Metrics.Keys)) {
        if ([string]$name -cnotin $metricNames) {
            throw "Unsupported usage metric: $name"
        }
    }
    $usage = [ordered]@{}
    foreach ($name in $metricNames) {
        $value = if ($Metrics.Contains($name)) { $Metrics[$name] } else { $null }
        $usage[$name] = New-UsageMetricValue -Name $name -Value $value
    }

    $event = [pscustomobject][ordered]@{
        schema_version = 1
        event_id = $EventId
        source_event_id = $SourceEventId
        session_id = $SessionId
        turn_id = $TurnId
        occurred_at = $occurred.ToString('o')
        provider = [string]$Identity.provider
        identity = $Identity
        model = [pscustomobject][ordered]@{
            status = if ([string]::IsNullOrWhiteSpace($Model)) {
                'unavailable'
            } else { 'observed' }
            value = if ([string]::IsNullOrWhiteSpace($Model)) {
                $null
            } else { $Model.Trim() }
        }
        usage = [pscustomobject]$usage
    }
    Assert-UsageSchemaValue `
        -Value $event `
        -SchemaFileName 'usage-events.schema.json' `
        -Label 'Usage event'
    return $event
}

Export-ModuleMember -Function @(
    'New-ProjectDUsageIdentifier',
    'Read-ProjectDUsageAccountProfiles',
    'Read-ProjectDUsageDeviceProfile',
    'ConvertTo-ProjectDCodexAccountObservation',
    'ConvertTo-ProjectDClaudeAccountObservation',
    'Resolve-ProjectDUsageIdentity',
    'Write-ProjectDUsageIdentityDiagnostic',
    'New-ProjectDUsageEvent'
)
