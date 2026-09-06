[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('codex', 'claude')]
    [string]$HostName,
    # Optional: when omitted, the most recently written decision file for
    # this host is auto-discovered under its runtime-policy directory. This
    # only changes WHICH existing, already-validated deny/observe decision
    # is used as seed evidence for freshness/provenance -- it does not
    # relax any of the checks below (schema, host_run_id identity, policy
    # digest, host_observable, non-unclassified) and it never widens what
    # is granted, since the grant contents still come from -Capability/
    # -TargetClass or -CapabilitySet, which the user still types the exact
    # confirmation phrase for.
    [string]$DecisionPath,
    [ValidateSet(
        'workspace-write',
        'command-execute',
        'external-write',
        'repository-mutate',
        'credential-use',
        'production-mutate'
    )]
    [string]$Capability,
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$TargetClass,
    # Named bundles of (capability, target_class) pairs frequently needed
    # together in one editing session, so one real-terminal confirmation
    # grants all of them instead of one confirmation per pair. Every pair
    # in every bundle keeps allow_external=false, allow_destructive=false;
    # a bundle can never grant production-mutate or an external/destructive
    # command-execute -- those remain single-grant, explicit, hard-gated
    # invocations only (see the checks below).
    [ValidateSet('governance-dev')]
    [string]$CapabilitySet,
    [switch]$AllowExternal,
    [switch]$AllowDestructive,
    [ValidateRange(1, 1440)]
    [int]$ExpiresInMinutes = 30,
    [Parameter(Mandatory)]
    [switch]$ExplicitUserAuthorization,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\RuntimePolicy.psm1') -Force

if ([Console]::IsInputRedirected) {
    throw (
        'Task authorization issuance requires a real interactive user ' +
        'terminal; redirected agent/tool input is not accepted.'
    )
}
if (-not $ExplicitUserAuthorization) {
    throw 'Task authorization issuance requires explicit user authorization.'
}

$capabilitySets = @{
    'governance-dev' = @(
        [pscustomobject]@{
            capability = 'repository-mutate'
            target_class = 'governance-control'
        }
        [pscustomobject]@{
            capability = 'workspace-write'
            target_class = 'workspace-file'
        }
        [pscustomobject]@{
            capability = 'repository-mutate'
            target_class = 'repository-state'
        }
    )
}

$usingCapabilitySet = -not [string]::IsNullOrWhiteSpace($CapabilitySet)
$usingSinglePair = (
    -not [string]::IsNullOrWhiteSpace($Capability) -or
    -not [string]::IsNullOrWhiteSpace($TargetClass)
)
if ($usingCapabilitySet -and $usingSinglePair) {
    throw 'Specify either -CapabilitySet or -Capability/-TargetClass, not both.'
}
if (-not $usingCapabilitySet -and -not $usingSinglePair) {
    throw 'Specify -CapabilitySet, or both -Capability and -TargetClass.'
}
if ($usingSinglePair -and (
    [string]::IsNullOrWhiteSpace($Capability) -or
    [string]::IsNullOrWhiteSpace($TargetClass)
)) {
    throw '-Capability and -TargetClass must both be supplied together.'
}
if ($usingCapabilitySet -and ($AllowExternal -or $AllowDestructive)) {
    throw (
        '-CapabilitySet bundles are fixed at external=false, ' +
        'destructive=false; use -Capability/-TargetClass for a grant ' +
        'that needs -AllowExternal or -AllowDestructive.'
    )
}
$requestedGrants = if ($usingCapabilitySet) {
    @($capabilitySets[$CapabilitySet] | ForEach-Object {
        [pscustomobject]@{
            capability = $_.capability
            target_class = $_.target_class
            allow_external = $false
            allow_destructive = $false
        }
    })
} else {
    @([pscustomobject]@{
        capability = $Capability
        target_class = $TargetClass
        allow_external = [bool]$AllowExternal
        allow_destructive = [bool]$AllowDestructive
    })
}
foreach ($requestedGrant in $requestedGrants) {
    if ($requestedGrant.capability -eq 'production-mutate') {
        if (-not $requestedGrant.allow_external -or -not $requestedGrant.allow_destructive) {
            throw 'Production mutation requires explicit external and destructive grants.'
        }
    }
    if (
        $requestedGrant.capability -eq 'command-execute' -and
        (-not $requestedGrant.allow_external -or -not $requestedGrant.allow_destructive)
    ) {
        throw (
            'Arbitrary command execution is open-world and requires explicit ' +
            'external and destructive grants.'
        )
    }
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw 'ProjectRoot does not exist.'
}
if (Test-PathHasReparsePoint -Root $root -ResolvedPath $root) {
    throw 'ProjectRoot must not be a reparse point.'
}
if ([string]::IsNullOrWhiteSpace($DecisionPath)) {
    $autoDiscoverDirectory = [IO.Path]::GetFullPath((Join-Path $root (
        ".local\governance\runtime-policy\$HostName"
    )))
    if (-not (Test-Path -LiteralPath $autoDiscoverDirectory -PathType Container)) {
        throw (
            'No -DecisionPath given and no runtime-policy directory exists ' +
            'for this host to auto-discover one from.'
        )
    }
    $autoDiscovered = Get-ChildItem -LiteralPath $autoDiscoverDirectory `
        -Filter 'decision-call-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $autoDiscovered) {
        throw (
            'No -DecisionPath given and no decision files were found to ' +
            'auto-discover for this host.'
        )
    }
    $DecisionPath = $autoDiscovered.FullName
}
$decisionFullPath = [IO.Path]::GetFullPath($DecisionPath)
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
if (-not $decisionFullPath.StartsWith(
    $rootPrefix, [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'DecisionPath must remain inside ProjectRoot.'
}
if (Test-PathHasReparsePoint -Root $root -ResolvedPath $decisionFullPath) {
    throw 'DecisionPath must not cross a reparse point.'
}
if (-not (Test-Path -LiteralPath $decisionFullPath -PathType Leaf)) {
    throw 'DecisionPath does not exist.'
}
if ((Get-Item -LiteralPath $decisionFullPath -Force).Length -gt 256KB) {
    throw 'DecisionPath exceeds its size limit.'
}
$decisionDirectory = [IO.Path]::GetFullPath((Join-Path $root (
    ".local\governance\runtime-policy\$HostName"
)))
if (-not ([IO.Path]::GetDirectoryName($decisionFullPath)).Equals(
    $decisionDirectory, [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'DecisionPath must be a host runtime-policy decision file.'
}
if ([IO.Path]::GetFileName($decisionFullPath) -cnotmatch
    '^decision-call-[a-f0-9]{32}\.json$') {
    throw 'DecisionPath filename is not a runtime hook decision identity.'
}

$decisionSchema = Join-Path $root (
    'evals\schemas\governance-runtime-policy-decisions.schema.json'
)
$authorizationSchema = Join-Path $root (
    'evals\schemas\governance-task-authorizations.schema.json'
)
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$decisionJson = $utf8.GetString([IO.File]::ReadAllBytes($decisionFullPath))
if (-not (Test-Json -Json $decisionJson -SchemaFile $decisionSchema -ErrorAction Stop)) {
    throw 'DecisionPath is not a valid runtime policy decision.'
}
$decision = $decisionJson | ConvertFrom-Json
$currentPolicyDigest = Get-ProjectDRuntimePolicyDigest -ProjectRoot $root
if (
    [string]$decision.policy.policy_id -cne 'runtime-governance-v2' -or
    [int]$decision.policy.policy_version -ne 1 -or
    [string]$decision.policy.policy_digest -cne $currentPolicyDigest
) {
    throw 'Decision policy identity does not match the current runtime policy.'
}
$decisionFileId = [IO.Path]::GetFileNameWithoutExtension($decisionFullPath)
if ([string]$decision.decision_id -cne $decisionFileId) {
    throw 'Decision identity does not match its filename.'
}
$callSuffix = $decisionFileId.Substring('decision-'.Length)
if ([string]$decision.operation_ref -cne "operation-$callSuffix") {
    throw 'Decision operation identity is inconsistent.'
}
if ([string]$decision.host_run_id -cnotmatch "^$HostName-session-[a-f0-9]{32}$") {
    throw 'Decision host identity does not match HostName.'
}
$sessionSuffix = ([string]$decision.host_run_id).Substring($HostName.Length + 1)
if ([string]$decision.task_ref -cne "host-hook-$sessionSuffix") {
    throw 'Decision task identity is inconsistent with its host run.'
}
if (-not [bool]$decision.coverage.host_observable) {
    throw 'DecisionPath is not host-observable runtime evidence.'
}
if ([string]$decision.request.capability -ceq 'unclassified-effect') {
    throw 'An unclassified effect cannot be used as an authorization source.'
}

$confirmationPhrase = if ($usingCapabilitySet) {
    "AUTHORIZE $HostName SET $CapabilitySet"
} else {
    "AUTHORIZE $HostName $Capability $TargetClass"
}
$grantSummary = ($requestedGrants | ForEach-Object {
    "$($_.capability)/$($_.target_class) (external=$($_.allow_external), destructive=$($_.allow_destructive))"
}) -join '; '
$confirmation = Read-Host (
    "Grant $grantSummary, expires=${ExpiresInMinutes}m. " +
    "Type '$confirmationPhrase' to continue"
)
if ([string]$confirmation -cne $confirmationPhrase) {
    throw 'Task authorization confirmation did not match the required phrase.'
}

$issuedAt = [DateTimeOffset]::UtcNow
$sourceDigest = Get-CanonicalTextSha256 -Path $decisionFullPath
$grantsSeedText = (
    @($requestedGrants | Sort-Object capability, target_class | ForEach-Object {
        "$($_.capability):$($_.target_class):$($_.allow_external):$($_.allow_destructive)"
    })
) -join '|'
$authorizationSeed = @(
    $sourceDigest,
    $issuedAt.ToString('o'),
    $grantsSeedText,
    $ExpiresInMinutes
) -join "`0"
$authorizationDigest = Get-TextSha256 -Text $authorizationSeed
$authorizationId = 'authorization-' + $authorizationDigest.Substring(7, 24)

$directory = Join-Path $root ".local\governance\task-authorizations\$HostName"
$directory = [IO.Path]::GetFullPath($directory)
if (-not $directory.StartsWith(
    $rootPrefix, [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Authorization directory resolves outside ProjectRoot.'
}
New-Item -ItemType Directory -Path $directory -Force | Out-Null
if (Test-PathHasReparsePoint -Root $root -ResolvedPath $directory) {
    throw 'Authorization directory must not cross a reparse point.'
}
$path = Join-Path $directory "$([string]$decision.task_ref).json"

# Merge with any existing, still-current, still-unexpired grant envelope for
# this task_ref instead of unconditionally overwriting it. A single-slot
# envelope forced re-authorizing every previously granted capability each
# time a different one was needed in the same task; merging removes that
# friction without loosening any check below (confirmation phrase, real
# terminal, decision provenance, and expiry all still apply per issuance).
$carriedGrants = @()
if (Test-Path -LiteralPath $path -PathType Leaf) {
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $path) {
        throw 'Authorization path must not cross a reparse point.'
    }
    if ((Get-Item -LiteralPath $path -Force).Length -le 256KB) {
        $existingAuthJson = $utf8.GetString([IO.File]::ReadAllBytes($path))
        if (Test-Json -Json $existingAuthJson -SchemaFile $authorizationSchema `
            -ErrorAction SilentlyContinue) {
            $existingAuth = $existingAuthJson | ConvertFrom-Json
            $existingExpiresAt = [DateTimeOffset]::Parse(
                [string]$existingAuth.expires_at
            )
            if (
                [string]$existingAuth.task_ref -ceq [string]$decision.task_ref -and
                [string]$existingAuth.host_run_id -ceq [string]$decision.host_run_id -and
                [string]$existingAuth.policy.policy_id -ceq 'runtime-governance-v2' -and
                [int]$existingAuth.policy.policy_version -eq 1 -and
                [string]$existingAuth.policy.policy_digest -ceq $currentPolicyDigest -and
                $existingExpiresAt -gt $issuedAt
            ) {
                $carriedGrants = @($existingAuth.grants | Where-Object {
                    $existingGrant = $_
                    -not (@($requestedGrants | Where-Object {
                        [string]$_.capability -ceq [string]$existingGrant.capability -and
                        [string]$_.target_class -ceq [string]$existingGrant.target_class
                    }).Count -gt 0)
                })
            }
        }
    }
}
$mergedGrants = @($carriedGrants) + @($requestedGrants | ForEach-Object {
    [pscustomobject][ordered]@{
        capability = $_.capability
        target_class = $_.target_class
        allow_external = [bool]$_.allow_external
        allow_destructive = [bool]$_.allow_destructive
    }
})
if ($mergedGrants.Count -gt 64) {
    throw 'Merged task authorization would exceed the maximum grant count.'
}

$document = [pscustomobject][ordered]@{
    schema_version = 1
    authorization_id = $authorizationId
    source_decision_id = [string]$decision.decision_id
    task_ref = [string]$decision.task_ref
    host_run_id = [string]$decision.host_run_id
    issued_at = $issuedAt.ToString('o')
    expires_at = $issuedAt.AddMinutes($ExpiresInMinutes).ToString('o')
    policy = [pscustomobject][ordered]@{
        policy_id = [string]$decision.policy.policy_id
        policy_version = [int]$decision.policy.policy_version
        policy_digest = [string]$decision.policy.policy_digest
    }
    authorization = [pscustomobject][ordered]@{
        basis = 'explicit-current-task'
        scope_match = 'exact'
        authorized_by = 'user'
    }
    grants = $mergedGrants
    privacy = [pscustomobject][ordered]@{
        content_mode = 'metadata-only'
        contains_raw_prompt = $false
        contains_chain_of_thought = $false
        contains_secret_values = $false
        contains_tool_arguments = $false
        contains_tool_output = $false
    }
}
$json = $document | ConvertTo-Json -Depth 32
if (-not (Test-Json -Json $json -SchemaFile $authorizationSchema -ErrorAction Stop)) {
    throw 'Generated task authorization envelope does not conform to its schema.'
}
if (
    (Test-Path -LiteralPath $path) -and
    (Test-PathHasReparsePoint -Root $root -ResolvedPath $path)
) {
    throw 'Authorization path must not cross a reparse point.'
}
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
if ($bytes.Length -gt 256KB) {
    throw 'Generated task authorization envelope exceeds its size limit.'
}
$temporary = Join-Path $directory (
    ".authorization-$([Guid]::NewGuid().ToString('N')).tmp"
)
try {
    $stream = [IO.FileStream]::new(
        $temporary,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None,
        4096,
        [IO.FileOptions]::WriteThrough
    )
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
    [IO.File]::Move($temporary, $path, $true)
} finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
        Remove-Item -LiteralPath $temporary -Force
    }
}

[pscustomobject]@{
    authorization_id = $document.authorization_id
    source_decision_id = $document.source_decision_id
    task_ref = $document.task_ref
    host_run_id = $document.host_run_id
    granted = @($requestedGrants | ForEach-Object {
        "$($_.capability)/$($_.target_class)"
    })
    expires_at = $document.expires_at
    path = $path
} | ConvertTo-Json -Depth 8
