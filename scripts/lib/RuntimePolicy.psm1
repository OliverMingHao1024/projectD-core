Set-StrictMode -Version Latest

function Test-RuntimePolicyPathHasReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ResolvedPath
    )

    $rootItem = Get-Item -LiteralPath $Root -Force
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        return $true
    }
    $relative = $ResolvedPath.Substring($Root.Length).TrimStart('\', '/')
    $current = $Root
    foreach ($part in @($relative -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                return $true
            }
        }
    }
    return $false
}

function Get-JsonStringProperty {
    param(
        [Parameter(Mandatory)][Text.Json.JsonElement]$Element,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
        return $null
    }
    foreach ($property in $Element.EnumerateObject()) {
        if ($property.Name -cne $Name) { continue }
        if ($property.Value.ValueKind -ne [Text.Json.JsonValueKind]::String) {
            return $null
        }
        return $property.Value.GetString()
    }
    return $null
}

function Test-ProjectDOperationToken {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Tokens
    )

    foreach ($token in $Tokens) {
        if ($Name -match "(?i)(^|[^a-z0-9])$([regex]::Escape($token))([^a-z0-9]|`$)") {
            return $true
        }
    }
    return $false
}

function Get-ProjectDWriteTargets {
    param(
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)][Text.Json.JsonElement]$ToolInput
    )

    if ($ToolName -ceq 'apply_patch') {
        $canonicalPatch = Get-JsonStringProperty -Element $ToolInput `
            -Name 'command'
        $compatibilityPatch = Get-JsonStringProperty -Element $ToolInput `
            -Name 'patch'
        if (
            -not [string]::IsNullOrWhiteSpace($canonicalPatch) -and
            -not [string]::IsNullOrWhiteSpace($compatibilityPatch) -and
            $canonicalPatch -cne $compatibilityPatch
        ) {
            return @()
        }
        $patch = if (-not [string]::IsNullOrWhiteSpace($canonicalPatch)) {
            $canonicalPatch
        } else { $compatibilityPatch }
        if ([string]::IsNullOrWhiteSpace($patch)) { return @() }
        $targets = @()
        foreach ($match in [regex]::Matches(
            $patch,
            '(?m)^\*\*\*\s+(?<operation>Add|Update|Delete)\s+File:\s*(?<path>[^\r\n]+?)\s*$'
        )) {
            $targets += [pscustomobject][ordered]@{
                path = $match.Groups['path'].Value
                destructive = $match.Groups['operation'].Value -ceq 'Delete'
            }
        }
        foreach ($match in [regex]::Matches(
            $patch,
            '(?m)^\*\*\*\s+Move\s+to:\s*(?<path>[^\r\n]+?)\s*$'
        )) {
            $targets += [pscustomobject][ordered]@{
                path = $match.Groups['path'].Value
                destructive = $true
            }
        }
        return @($targets)
    }

    foreach ($propertyName in @('file_path', 'notebook_path', 'path')) {
        $path = Get-JsonStringProperty -Element $ToolInput -Name $propertyName
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            return @([pscustomobject][ordered]@{
                path = $path
                destructive = $false
            })
        }
    }
    return @()
}

function Resolve-ProjectDWriteClassification {
    param(
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)][Text.Json.JsonElement]$ToolInput,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    $targets = @(Get-ProjectDWriteTargets -ToolName $ToolName `
        -ToolInput $ToolInput)
    if ($targets.Count -eq 0) {
        return [pscustomobject][ordered]@{
            capability = 'unclassified-effect'
            target_class = 'unclassified-target'
            durable = $true
            external = $true
            destructive = $true
            reversible = 'unknown'
            classification_source = 'unclassified'
        }
    }

    $containsRuntimeState = $false
    $containsGovernanceControl = $false
    $containsRepositoryState = $false
    $containsUnsafeTarget = $false
    $destructive = $false
    foreach ($target in $targets) {
        $destructive = $destructive -or [bool]$target.destructive
        try {
            $candidate = if ([IO.Path]::IsPathRooted([string]$target.path)) {
                [IO.Path]::GetFullPath([string]$target.path)
            } else {
                [IO.Path]::GetFullPath((Join-Path $root ([string]$target.path)))
            }
            if (-not $candidate.StartsWith(
                $rootPrefix, [StringComparison]::OrdinalIgnoreCase
            )) {
                $containsUnsafeTarget = $true
                continue
            }
            if (Test-RuntimePolicyPathHasReparsePoint -Root $root `
                -ResolvedPath $candidate) {
                $containsUnsafeTarget = $true
                continue
            }
            $relative = [IO.Path]::GetRelativePath($root, $candidate)
            $relative = $relative.Replace('\', '/').ToLowerInvariant()
            if ($relative -match '^\.local/governance/(task-authorizations|runtime-policy|operation-hooks)(/|$)') {
                $containsRuntimeState = $true
            } elseif ($relative -match '^\.git(/|$)') {
                $containsRepositoryState = $true
            } elseif (
                $relative -match '^(\.codex|\.claude)(/|$)' -or
                $relative -match '^core/constitution(/|$)' -or
                $relative -match '^vault/governance(/|$)' -or
                $relative -match '^scripts/(governance-|projectd-check\.ps1$|codex-governance-hook\.cmd$|lib/(runtimepolicy|governancecommon)\.psm1$|tests/governance-)' -or
                $relative -match '^evals/(governance-assets\.json$|schemas/governance-)' -or
                $relative -match '^\.github/workflows/governance'
            ) {
                $containsGovernanceControl = $true
            }
        } catch {
            $containsUnsafeTarget = $true
        }
    }

    if ($containsRuntimeState) {
        return [pscustomobject][ordered]@{
            capability = 'unclassified-effect'
            target_class = 'runtime-governance-state'
            durable = $true
            external = $false
            destructive = $true
            reversible = 'unknown'
            classification_source = 'operation-payload'
        }
    }
    if ($containsUnsafeTarget) {
        return [pscustomobject][ordered]@{
            capability = 'unclassified-effect'
            target_class = 'unclassified-target'
            durable = $true
            external = $true
            destructive = $true
            reversible = 'unknown'
            classification_source = 'unclassified'
        }
    }
    if ($containsGovernanceControl) {
        return [pscustomobject][ordered]@{
            capability = 'repository-mutate'
            target_class = 'governance-control'
            durable = $true
            external = $false
            destructive = $destructive
            reversible = 'unknown'
            classification_source = 'operation-payload'
        }
    }
    if ($containsRepositoryState) {
        return [pscustomobject][ordered]@{
            capability = 'repository-mutate'
            target_class = 'repository-state'
            durable = $true
            external = $false
            destructive = $destructive
            reversible = 'unknown'
            classification_source = 'operation-payload'
        }
    }
    return [pscustomobject][ordered]@{
        capability = 'workspace-write'
        target_class = 'workspace-file'
        durable = $true
        external = $false
        destructive = $destructive
        reversible = 'unknown'
        classification_source = 'operation-payload'
    }
}

function Get-ProjectDRuntimeRequest {
    param(
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)][Text.Json.JsonElement]$ToolInput,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $name = $ToolName.ToLowerInvariant()
    $capability = 'unclassified-effect'
    $targetClass = 'unclassified-target'
    $classificationSource = 'tool-name-fallback'
    $durable = $false
    $external = $false
    $destructive = $false
    $reversible = 'unknown'

    if ($name -match '^(read|glob|grep|list|search_files|find)$') {
        $capability = 'local-read'
        $targetClass = 'workspace-source'
        $classificationSource = 'deterministic-rule'
        $reversible = 'yes'
    } elseif ($name -match '^(askuserquestion|elicitation)$') {
        $capability = 'local-read'
        $targetClass = 'user-input'
        $classificationSource = 'deterministic-rule'
        $reversible = 'yes'
    } elseif ($name -match '^(apply_patch|edit|write|notebookedit)$') {
        $writeClassification = Resolve-ProjectDWriteClassification `
            -ToolName $name -ToolInput $ToolInput -ProjectRoot $ProjectRoot
        $capability = $writeClassification.capability
        $targetClass = $writeClassification.target_class
        $classificationSource = $writeClassification.classification_source
        $durable = $writeClassification.durable
        $external = $writeClassification.external
        $destructive = $writeClassification.destructive
        $reversible = $writeClassification.reversible
    } elseif ($name -match '(bash|shell|powershell|exec|command|terminal)') {
        $command = Get-JsonStringProperty -Element $ToolInput -Name 'command'
        if ([string]::IsNullOrWhiteSpace($command)) {
            $command = Get-JsonStringProperty -Element $ToolInput -Name 'cmd'
        }
        if (-not [string]::IsNullOrWhiteSpace($command)) {
            if ($command -match '(?i)(?:^|[;&|\r\n])\s*(git\s+(add|commit|merge|rebase|cherry-pick|reset|restore|checkout|switch|branch|tag|push|pull)\b|gh\s+(pr|release)\s+(create|merge|close|edit|delete)\b)') {
                $capability = 'repository-mutate'
                $targetClass = 'repository-state'
                $classificationSource = 'operation-payload'
                $durable = $true
                $external = $command -match '(?i)\bgit\s+(push|pull)\b|\bgh\s+'
                $destructive = $command -match '(?i)\bgit\s+reset\b|\bgit\s+push\b.*(--force|-f)\b|\bgh\s+.*\b(delete|merge|close)\b'
                $reversible = 'unknown'
            } else {
                $capability = 'command-execute'
                $targetClass = 'command-environment'
                $classificationSource = 'operation-payload'
                $durable = $true
                $external = $true
                $destructive = $true
                $reversible = 'unknown'
            }
        } else {
            $capability = 'command-execute'
            $targetClass = 'command-environment'
            $durable = $true
            $external = $true
            $destructive = $true
        }
    } elseif ($name -match '(web|fetch|http|browser)') {
        if (Test-ProjectDOperationToken -Name $name -Tokens @(
            'send', 'create', 'update', 'delete', 'post', 'put', 'patch',
            'upload', 'publish', 'submit', 'click', 'type'
        )) {
            $capability = 'external-write'
            $targetClass = 'external-service'
            $durable = $true
            $external = $true
            $reversible = 'unknown'
        } elseif (Test-ProjectDOperationToken -Name $name -Tokens @(
            'read', 'get', 'list', 'search', 'find', 'fetch', 'open',
            'screenshot', 'navigate'
        )) {
            $capability = 'network-read'
            $targetClass = 'external-source'
            $external = $true
            $reversible = 'yes'
        } else {
            $classificationSource = 'unclassified'
            $external = $true
            $durable = $true
            $destructive = $true
        }
    } elseif ($name -match '(mcp|connector)') {
        if (Test-ProjectDOperationToken -Name $name -Tokens @(
            'send', 'create', 'update', 'delete', 'write', 'edit', 'post',
            'put', 'patch', 'upload', 'publish', 'merge', 'deploy', 'submit'
        )) {
            $capability = 'external-write'
            $targetClass = 'external-service'
            $durable = $true
            $external = $true
            $reversible = 'unknown'
        } elseif (Test-ProjectDOperationToken -Name $name -Tokens @(
            'read', 'get', 'list', 'search', 'find', 'fetch', 'open'
        )) {
            $capability = 'network-read'
            $targetClass = 'external-source'
            $external = $true
            $reversible = 'yes'
        } else {
            $classificationSource = 'unclassified'
            $external = $true
            $durable = $true
            $destructive = $true
        }
    } else {
        $classificationSource = 'unclassified'
        $external = $true
        $durable = $true
        $destructive = $true
    }

    $outcome = if ($capability -in @('local-read', 'network-read')) {
        'observe-only'
    } else {
        'require-authorization'
    }
    $reasonCodes = if ($capability -eq 'unclassified-effect') {
        @('unclassified-effect', 'task-authorization-unavailable')
    } elseif ($outcome -eq 'observe-only') {
        @('non-mutating-capability', 'task-authorization-unavailable')
    } else {
        @('effectful-capability', 'task-authorization-unavailable')
    }

    return [pscustomobject][ordered]@{
        capability = $capability
        target_class = $targetClass
        effect = [pscustomobject][ordered]@{
            durable = $durable
            external = $external
            destructive = $destructive
            reversible = $reversible
        }
        classification_source = $classificationSource
        decision_outcome = $outcome
        reason_codes = $reasonCodes
    }
}

function Resolve-ProjectDRuntimeAuthorization {
    param(
        [Parameter(Mandatory)]$RuntimeRequest,
        $Envelope,
        [Parameter(Mandatory)][string]$TaskRef,
        [Parameter(Mandatory)][string]$HostRunId,
        [Parameter(Mandatory)][string]$PolicyDigest,
        [string]$PolicyId = 'runtime-governance-v2',
        [int]$PolicyVersion = 1,
        [switch]$AllowContractAuthorizationFixture,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    $capability = [string]$RuntimeRequest.capability
    if ($capability -in @('local-read', 'network-read')) {
        return [pscustomobject][ordered]@{
            state = 'unavailable'
            basis = 'unavailable'
            scope_match = 'unknown'
            outcome = [string]$RuntimeRequest.decision_outcome
            enforcement = 'advisory'
            reason_codes = @($RuntimeRequest.reason_codes)
        }
    }

    if ($null -eq $Envelope) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'unknown'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = if (
                [string]$RuntimeRequest.capability -ceq 'unclassified-effect'
            ) {
                @('unclassified-effect', 'task-authorization-required')
            } else {
                @('task-authorization-required')
            }
        }
    }

    if (
        [string]$Envelope.task_ref -cne $TaskRef -or
        [string]$Envelope.host_run_id -cne $HostRunId
    ) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('authorization-envelope-identity-mismatch')
        }
    }

    if (
        [string]$Envelope.policy.policy_id -cne $PolicyId -or
        [int]$Envelope.policy.policy_version -ne $PolicyVersion -or
        [string]$Envelope.policy.policy_digest -cne $PolicyDigest
    ) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('authorization-envelope-policy-mismatch')
        }
    }

    if (
        [string]$Envelope.authorization.authorized_by -ceq 'contract-fixture' -and
        -not $AllowContractAuthorizationFixture
    ) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('contract-authorization-not-accepted-live')
        }
    }

    $issuedAt = [DateTimeOffset]::Parse([string]$Envelope.issued_at)
    $expiresAt = [DateTimeOffset]::Parse([string]$Envelope.expires_at)
    if ($issuedAt -gt $Now -or $expiresAt -le $issuedAt) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('authorization-envelope-time-invalid')
        }
    }
    if (($expiresAt - $issuedAt) -gt [TimeSpan]::FromHours(24)) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('authorization-envelope-lifetime-invalid')
        }
    }
    if ($expiresAt -le $Now) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('authorization-envelope-expired')
        }
    }

    if ($capability -eq 'unclassified-effect') {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'unknown'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('unclassified-effect')
        }
    }

    $matchingGrant = @($Envelope.grants | Where-Object {
        [string]$_.capability -ceq $capability -and
        [string]$_.target_class -ceq [string]$RuntimeRequest.target_class
    } | Select-Object -First 1)
    if ($matchingGrant.Count -eq 0) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('capability-not-granted')
        }
    }

    $grant = $matchingGrant[0]
    if ([bool]$RuntimeRequest.effect.external -and -not [bool]$grant.allow_external) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('external-effect-not-granted')
        }
    }
    if ([bool]$RuntimeRequest.effect.destructive -and -not [bool]$grant.allow_destructive) {
        return [pscustomobject][ordered]@{
            state = 'not-authorized'
            basis = 'none'
            scope_match = 'mismatch'
            outcome = 'deny'
            enforcement = 'enforced'
            reason_codes = @('destructive-effect-not-granted')
        }
    }

    return [pscustomobject][ordered]@{
        state = 'verified'
        basis = [string]$Envelope.authorization.basis
        scope_match = [string]$Envelope.authorization.scope_match
        outcome = 'allow'
        enforcement = 'enforced'
        reason_codes = @('authorized-task-scope')
    }
}

function Get-ProjectDRuntimePolicyDigest {
    param(
        [string]$ProjectRoot,
        [string]$GovernanceCommonPath,
        [string]$RuntimePolicyPath,
        [string]$HostHookPath,
        [string]$AuthorizationIssuerPath,
        [string]$RuntimePolicySchemaPath,
        [string]$TaskAuthorizationSchemaPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $GovernanceCommonPath = Join-Path $root `
            'scripts/lib/GovernanceCommon.psm1'
        $RuntimePolicyPath = Join-Path $root 'scripts/lib/RuntimePolicy.psm1'
        $HostHookPath = Join-Path $root `
            'scripts/governance-host-operation-hook.ps1'
        $AuthorizationIssuerPath = Join-Path $root `
            'scripts/governance-task-authorization.ps1'
        $RuntimePolicySchemaPath = Join-Path $root `
            'evals/schemas/governance-runtime-policy-decisions.schema.json'
        $TaskAuthorizationSchemaPath = Join-Path $root `
            'evals/schemas/governance-task-authorizations.schema.json'
    }
    $components = [ordered]@{
        'governance-common-module' = $GovernanceCommonPath
        'runtime-policy-module' = $RuntimePolicyPath
        'host-operation-hook' = $HostHookPath
        'task-authorization-issuer' = $AuthorizationIssuerPath
        'runtime-policy-schema' = $RuntimePolicySchemaPath
        'task-authorization-schema' = $TaskAuthorizationSchemaPath
    }
    foreach ($entry in $components.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            throw "Runtime policy component path is required: $($entry.Key)"
        }
    }
    $builder = [Text.StringBuilder]::new()
    $decoder = [Text.UTF8Encoding]::new($false, $true)
    foreach ($entry in $components.GetEnumerator()) {
        $label = [string]$entry.Key
        $path = [IO.Path]::GetFullPath([string]$entry.Value)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Runtime policy component is missing: $label"
        }
        if ((Get-Item -LiteralPath $path -Force).Length -gt 1MB) {
            throw "Runtime policy component is too large: $label"
        }
        if (
            (Get-Item -LiteralPath $path -Force).Attributes -band
                [IO.FileAttributes]::ReparsePoint
        ) {
            throw "Runtime policy component is a reparse point: $label"
        }
        $text = $decoder.GetString([IO.File]::ReadAllBytes($path))
        $text = $text -replace "\r\n?", "`n"
        [void]$builder.Append($label)
        [void]$builder.Append("`0")
        [void]$builder.Append($text)
        [void]$builder.Append("`0")
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())
    return 'sha256:' + [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function ConvertTo-LegacyOperationClassification {
    param([Parameter(Mandatory)]$RuntimeRequest)

    switch ([string]$RuntimeRequest.capability) {
        'local-read' {
            return [pscustomobject][ordered]@{
                effect_kind = 'tool'
                target = 'local-source'
                classification = 'source'
                external = $false
                destructive = $false
            }
        }
        'network-read' {
            return [pscustomobject][ordered]@{
                effect_kind = 'tool'
                target = 'external-service'
                classification = 'source'
                external = $true
                destructive = $false
            }
        }
        'workspace-write' {
            return [pscustomobject][ordered]@{
                effect_kind = 'durable-write'
                target = 'workspace-file'
                classification = 'action'
                external = $false
                destructive = [bool]$RuntimeRequest.effect.destructive
            }
        }
        default {
            return [pscustomobject][ordered]@{
                effect_kind = 'external-action'
                target = if ([string]$RuntimeRequest.target_class -eq 'command-environment') { 'command-environment' } else { 'external-service' }
                classification = 'action'
                external = [bool]$RuntimeRequest.effect.external
                destructive = [bool]$RuntimeRequest.effect.destructive
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Get-ProjectDRuntimeRequest',
    'Resolve-ProjectDRuntimeAuthorization',
    'Get-ProjectDRuntimePolicyDigest',
    'ConvertTo-LegacyOperationClassification'
)
