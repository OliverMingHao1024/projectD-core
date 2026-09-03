[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('codex', 'claude')]
    [string]$HostName,
    [Parameter(Mandatory)]
    [string]$DecisionPath,
    [Parameter(Mandatory)]
    [ValidateSet(
        'workspace-write',
        'command-execute',
        'external-write',
        'repository-mutate',
        'credential-use',
        'production-mutate'
    )]
    [string]$Capability,
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$TargetClass,
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

if ($Capability -eq 'production-mutate') {
    if (-not $AllowExternal -or -not $AllowDestructive) {
        throw 'Production mutation requires explicit external and destructive grants.'
    }
}
if (
    $Capability -eq 'command-execute' -and
    (-not $AllowExternal -or -not $AllowDestructive)
) {
    throw (
        'Arbitrary command execution is open-world and requires explicit ' +
        'external and destructive grants.'
    )
}

$confirmationPhrase = "AUTHORIZE $HostName $Capability $TargetClass"
$confirmation = Read-Host (
    "Grant external=$([bool]$AllowExternal), " +
    "destructive=$([bool]$AllowDestructive), " +
    "expires=${ExpiresInMinutes}m. Type '$confirmationPhrase' to continue"
)
if ([string]$confirmation -cne $confirmationPhrase) {
    throw 'Task authorization confirmation did not match the required phrase.'
}

$issuedAt = [DateTimeOffset]::UtcNow
$sourceDigest = Get-CanonicalTextSha256 -Path $decisionFullPath
$authorizationSeed = @(
    $sourceDigest,
    $issuedAt.ToString('o'),
    $Capability,
    $TargetClass,
    [bool]$AllowExternal,
    [bool]$AllowDestructive,
    $ExpiresInMinutes
) -join "`0"
$authorizationDigest = Get-TextSha256 -Text $authorizationSeed
$authorizationId = 'authorization-' + $authorizationDigest.Substring(7, 24)
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
    grants = @(
        [pscustomobject][ordered]@{
            capability = $Capability
            target_class = $TargetClass
            allow_external = [bool]$AllowExternal
            allow_destructive = [bool]$AllowDestructive
        }
    )
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
$path = Join-Path $directory "$($document.task_ref).json"
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
    capability = $Capability
    target_class = $TargetClass
    expires_at = $document.expires_at
    path = $path
} | ConvertTo-Json -Depth 8
