[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$ProjectionPath,
    [Parameter(Mandatory)][string]$AccountReadPath,
    [string]$AccountProfilesPath,
    [string]$DeviceProfilePath,
    [string]$ExpectedAccountId,
    [string]$LedgerPath
)

$ErrorActionPreference = 'Stop'
$usageContractPath = Join-Path $PSScriptRoot 'lib\UsageContract.psm1'
$usageLedgerPath = Join-Path $PSScriptRoot 'lib\UsageLedger.psm1'
$governanceCommonPath = Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1'
Import-Module $usageContractPath -Force -ErrorAction Stop
Import-Module $usageLedgerPath -Force -ErrorAction Stop
Import-Module $governanceCommonPath -Force -ErrorAction Stop

function Resolve-LocalUsageInput {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][long]$MaximumBytes
    )

    $localRoot = [IO.Path]::GetFullPath((Join-Path $Root '.local')).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolved = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $Root $Path))
    }
    $localPrefix = $localRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
        $localPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "$Label must stay inside ProjectRoot/.local."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Label does not exist."
    }
    if (Test-PathHasReparsePoint -Root $Root -ResolvedPath $resolved) {
        throw "$Label must not cross a reparse point."
    }
    if ((Get-Item -LiteralPath $resolved -Force).Length -gt $MaximumBytes) {
        throw "$Label exceeds its input size limit."
    }
    return $resolved
}

function Read-LocalUsageJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $json = $utf8.GetString([IO.File]::ReadAllBytes($Path))
        return $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "$Label is not valid UTF-8 JSON."
    }
}

function ConvertTo-LocalUsageTimestampText {
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [DateTimeOffset]) {
        return $Value.ToUniversalTime().ToString('o')
    }
    if ($Value -is [DateTime]) {
        return ([DateTimeOffset]$Value).ToUniversalTime().ToString('o')
    }
    return [string]$Value
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot must be an existing directory.'
}
if ([string]::IsNullOrWhiteSpace($AccountProfilesPath)) {
    $AccountProfilesPath = Join-Path $root (
        '.local\governance\usage-account-profiles.json'
    )
}
if ([string]::IsNullOrWhiteSpace($DeviceProfilePath)) {
    $DeviceProfilePath = Join-Path $root (
        '.local\governance\usage-device.json'
    )
}
if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
    $LedgerPath = Join-Path $root '.local\usage\codex-ledger.jsonl'
}

$resolvedProjection = Resolve-LocalUsageInput `
    -Root $root -Path $ProjectionPath `
    -Label 'Codex usage projection' -MaximumBytes 32KB
$resolvedAccountRead = Resolve-LocalUsageInput `
    -Root $root -Path $AccountReadPath `
    -Label 'Codex account observation' -MaximumBytes 16KB
$resolvedAccounts = Resolve-LocalUsageInput `
    -Root $root -Path $AccountProfilesPath `
    -Label 'Usage account profiles' -MaximumBytes 64KB
$resolvedDevice = Resolve-LocalUsageInput `
    -Root $root -Path $DeviceProfilePath `
    -Label 'Usage device profile' -MaximumBytes 4KB

$projection = Read-LocalUsageJson `
    -Path $resolvedProjection -Label 'Codex usage projection'
$projectionSchema = Join-Path $PSScriptRoot (
    '..\evals\schemas\codex-usage-projection.schema.json'
)
try {
    $projectionJson = $projection | ConvertTo-Json -Depth 32
    $projectionValid = Test-Json `
        -Json $projectionJson -SchemaFile $projectionSchema -ErrorAction Stop
    if (-not $projectionValid) {
        throw 'JSON Schema validation returned false.'
    }
} catch {
    throw 'Codex usage projection does not conform to its canonical schema.'
}

$accountRead = Read-LocalUsageJson `
    -Path $resolvedAccountRead -Label 'Codex account observation'
$profiles = Read-ProjectDUsageAccountProfiles -Path $resolvedAccounts
$device = Read-ProjectDUsageDeviceProfile -Path $resolvedDevice
$observation = ConvertTo-ProjectDCodexAccountObservation `
    -AccountRead $accountRead
$identityArgs = @{
    Observation = $observation
    AccountProfiles = $profiles
    DeviceProfile = $device
    CapturedAt = ConvertTo-LocalUsageTimestampText $projection.captured_at
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedAccountId)) {
    $identityArgs.ExpectedAccountId = $ExpectedAccountId
}
$identity = Resolve-ProjectDUsageIdentity @identityArgs
$event = ConvertTo-ProjectDCodexUsageEvent `
    -Projection $projection -Identity $identity
$result = Write-ProjectDUsageLedgerEvent `
    -Event $event -ProjectRoot $root -LedgerPath $LedgerPath
$result | ConvertTo-Json -Compress
