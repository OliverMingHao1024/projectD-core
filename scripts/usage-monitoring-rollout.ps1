[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check', 'Apply', 'Disable', 'Remove')]
    [string]$Mode,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('work', 'home', 'other')][string]$Environment = 'work',
    [switch]$AllowExport,
    [switch]$Confirm
)

<#
Rollout wiring for the Codex/Claude token-usage-monitoring contract
(docs/specs/token-usage-monitoring.md, #38-#44). This script only ever
touches files under ProjectRoot/.local -- it never writes to AGENTS.md,
CLAUDE.md, vault/, or any other session-init path, and it never starts
Codex, Claude, a model, or a network call. A missing or failing usage
tool always fails closed on its own invocation; it cannot block or
interrupt an unrelated Codex/Claude host session, because nothing here
runs as part of one.
#>

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\UsageContract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\UsageExportGate.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot must be an existing directory.'
}

$paths = [pscustomobject][ordered]@{
    device_profile = Join-Path $root '.local\governance\usage-device.json'
    account_profiles = Join-Path $root '.local\governance\usage-account-profiles.json'
    export_policy = Join-Path $root '.local\governance\usage-export-policy.json'
    usage_root = Join-Path $root '.local\usage'
}

function Get-UsageRolloutFileState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SchemaFileName
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            path = $Path; present = $false; valid = $null
        }
    }
    $schemaPath = Join-Path $PSScriptRoot "..\evals\schemas\$SchemaFileName"
    try {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $json = $utf8.GetString([IO.File]::ReadAllBytes($Path))
        $valid = Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop
    } catch {
        $valid = $false
    }
    return [pscustomobject][ordered]@{
        path = $Path; present = $true; valid = [bool]$valid
    }
}

function Get-UsageRolloutStatus {
    $device = Get-UsageRolloutFileState `
        -Path $paths.device_profile -SchemaFileName 'usage-device-profile.schema.json'
    $accounts = Get-UsageRolloutFileState `
        -Path $paths.account_profiles -SchemaFileName 'usage-account-profiles.schema.json'
    $policy = Get-UsageRolloutFileState `
        -Path $paths.export_policy -SchemaFileName 'usage-export-policy.schema.json'
    $exportAllowed = $false
    if ($policy.present -and $policy.valid) {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $policyValue = ($utf8.GetString(
            [IO.File]::ReadAllBytes($paths.export_policy)
        ) | ConvertFrom-Json)
        $exportAllowed = [bool]$policyValue.export_allowed
    }
    return [pscustomobject][ordered]@{
        device_profile = $device
        account_profiles = $accounts
        export_policy = $policy
        export_allowed = $exportAllowed
        usage_root_present = Test-Path -LiteralPath $paths.usage_root -PathType Container
    }
}

switch ($Mode) {
    'Check' {
        $status = Get-UsageRolloutStatus
        $status | ConvertTo-Json -Depth 8
        return
    }
    'Apply' {
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $paths.device_profile
        ) -Force | Out-Null
        if (-not (Test-Path -LiteralPath $paths.device_profile -PathType Leaf)) {
            $deviceId = New-ProjectDUsageIdentifier -Kind Device
            $device = [pscustomobject][ordered]@{
                schema_version = 1
                device_id = $deviceId
                environment = $Environment
            }
            $device | ConvertTo-Json -Depth 4 | Set-Content `
                -LiteralPath $paths.device_profile -Encoding utf8 -NoNewline
            Read-ProjectDUsageDeviceProfile -Path $paths.device_profile | Out-Null
        }
        # usage-account-profiles.json is intentionally never auto-generated:
        # it requires at least one real account_id/alias/email chosen by the
        # operator (schema requires a non-empty accounts array), and the
        # account_id must be reused as-is across every device for the same
        # account. See docs/operations/token-usage-monitoring.md.
        if (-not (Test-Path -LiteralPath $paths.export_policy -PathType Leaf)) {
            $policy = [pscustomobject][ordered]@{
                schema_version = 1
                export_allowed = [bool]$AllowExport
                policy_version = "rollout-$Environment-v1"
            }
            $policy | ConvertTo-Json -Depth 4 | Set-Content `
                -LiteralPath $paths.export_policy -Encoding utf8 -NoNewline
            Read-ProjectDUsageExportPolicy -Path $paths.export_policy | Out-Null
        }
        New-Item -ItemType Directory -Path $paths.usage_root -Force | Out-Null
        Get-UsageRolloutStatus | ConvertTo-Json -Depth 8
        return
    }
    'Disable' {
        if (-not (Test-Path -LiteralPath $paths.export_policy -PathType Leaf)) {
            Write-Output (
                'No export policy file exists; this device is already local-only.'
            )
            return
        }
        $policy = [pscustomobject][ordered]@{
            schema_version = 1
            export_allowed = $false
            policy_version = "rollout-$Environment-disabled"
        }
        $policy | ConvertTo-Json -Depth 4 | Set-Content `
            -LiteralPath $paths.export_policy -Encoding utf8 -NoNewline
        Write-Output 'Export disabled; local-only. Existing local data was not removed.'
        return
    }
    'Remove' {
        if (-not $Confirm) {
            throw (
                'Mode Remove permanently deletes local usage data ' +
                '(ledgers, exports, merge state, reports, diagnostics, and ' +
                'account/device/policy profiles). Re-run with -Confirm to proceed.'
            )
        }
        foreach ($target in @($paths.usage_root, $paths.device_profile,
            $paths.account_profiles, $paths.export_policy)) {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
        }
        Write-Output 'All local usage-monitoring data and configuration removed.'
        return
    }
}
