[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InventoryPath,
    [string]$InventorySchemaPath,
    [string]$BehaviorCatalogPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
    $InventoryPath = Join-Path $root 'evals\governance-assets.json'
}
if ([string]::IsNullOrWhiteSpace($InventorySchemaPath)) {
    $InventorySchemaPath = Join-Path $root (
        'evals\schemas\governance-assets.schema.json'
    )
}
if ([string]::IsNullOrWhiteSpace($BehaviorCatalogPath)) {
    $BehaviorCatalogPath = Join-Path $root 'evals\governance-behavior-cases.json'
}

function Test-HasProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)
    $null -ne $Value -and $Value.PSObject.Properties.Name -contains $Name
}

function Find-ForbiddenCredentialField {
    param($Value, [string]$Path = '$')
    $forbidden = @('secret', 'token', 'password', 'credential_value', 'value')
    if ($null -eq $Value) { return @() }
    $hits = @()
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -in $forbidden) {
                $hits += "$Path.$($property.Name)"
            }
            $hits += @(
                Find-ForbiddenCredentialField $property.Value `
                    "$Path.$($property.Name)"
            )
        }
    } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in $Value) {
            $hits += @(Find-ForbiddenCredentialField $item "$Path[$index]")
            $index++
        }
    }
    return $hits
}

function Find-SensitiveValue {
    param($Value, [string]$Path = '$')
    if ($null -eq $Value) { return @() }
    $hits = @()
    if ($Value -is [string]) {
        $patterns = @(
            '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
            '\bgh[pousr]_[A-Za-z0-9]{20,}\b',
            '\bgithub_pat_[A-Za-z0-9_]{20,}\b',
            '\bsk-[A-Za-z0-9_-]{20,}\b',
            '\bAKIA[0-9A-Z]{16}\b',
            '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}'
        )
        foreach ($pattern in $patterns) {
            if ($Value -match $pattern) {
                $hits += $Path
                break
            }
        }
    } elseif (
        $Value -is [Collections.IDictionary] -or
        $Value -is [pscustomobject]
    ) {
        foreach ($property in $Value.PSObject.Properties) {
            $hits += @(Find-SensitiveValue $property.Value "$Path.$($property.Name)")
        }
    } elseif ($Value -is [Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Value) {
            $hits += @(Find-SensitiveValue $item "$Path[$index]")
            $index++
        }
    }
    return $hits
}

function Test-PathHasReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ResolvedPath
    )
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

$errors = @()
$assets = @()
try {
    $inventoryJson = Get-Content -Raw -LiteralPath $InventoryPath
    if (-not (
        Test-Json -Json $inventoryJson -SchemaFile $InventorySchemaPath `
            -ErrorAction Stop
    )) {
        throw 'Inventory does not conform to its JSON Schema.'
    }
    $inventory = $inventoryJson | ConvertFrom-Json
    foreach ($field in @(Find-SensitiveValue $inventory)) {
        $errors += "Inventory contains a secret-like value at: $field"
    }
    if ($inventory.schema_version -ne 1) {
        $errors += 'Unsupported inventory schema_version.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$inventory.scope)) {
        $errors += 'Inventory scope is required.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$inventory.owner)) {
        $errors += 'Inventory owner is required.'
    }
    $catalog = Get-Content -Raw -LiteralPath $BehaviorCatalogPath |
        ConvertFrom-Json
    $caseIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($case in @($catalog.cases)) { [void]$caseIds.Add([string]$case.id) }

    foreach ($exclusion in @($inventory.coverage_exclusions)) {
        foreach ($field in @('id', 'reason', 'owner', 'discovery_trigger')) {
            if ([string]::IsNullOrWhiteSpace([string]$exclusion.$field)) {
                $errors += "Coverage exclusion must define $field."
            }
        }
    }

    $assets = @($inventory.assets)
    if ($assets.Count -eq 0) { $errors += 'Inventory must contain assets.' }
    $assetIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($asset in $assets) {
        $id = [string]$asset.id
        if ($id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or -not $assetIds.Add($id)) {
            $errors += "Invalid or duplicate asset id: $id"
        }
        if ($asset.kind -notin @(
            'agent', 'model', 'skill_catalog', 'tool', 'mcp', 'plugin',
            'credential', 'data_source'
        )) {
            $errors += "$id has an unsupported kind."
        }
        if ($asset.status -notin @('active', 'disabled', 'planned', 'retired')) {
            $errors += "$id has an unsupported status."
        }
        if ($asset.risk_tier -notin @('low', 'medium', 'high', 'critical')) {
            $errors += "$id has an unsupported risk_tier."
        }
        if ([string]::IsNullOrWhiteSpace([string]$asset.owner)) {
            $errors += "$id must define an owner."
        }
        foreach ($field in @('type', 'reference', 'version')) {
            if ([string]::IsNullOrWhiteSpace([string]$asset.source.$field)) {
                $errors += "$id source must define $field."
            }
        }
        if (
            $asset.status -eq 'active' -and
            $asset.kind -in @('tool', 'mcp', 'plugin') -and
            [string]$asset.source.integrity -cnotmatch '^sha256:[A-Fa-f0-9]{64}$'
        ) {
            $errors += "$id active executable asset lacks SHA-256 integrity evidence."
        }
        if ($asset.source.type -eq 'repository-local') {
            $reference = [string]$asset.source.reference
            if (
                [IO.Path]::IsPathRooted($reference) -or
                $reference -split '[\\/]' -contains '..'
            ) {
                $errors += "$id has an unsafe repository-local reference."
            } else {
                $resolved = [IO.Path]::GetFullPath((Join-Path $root $reference))
                if (
                    -not $resolved.StartsWith(
                        $root + [IO.Path]::DirectorySeparatorChar,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -or
                    -not (Test-Path -LiteralPath $resolved)
                ) {
                    $errors += "$id repository-local reference is missing or outside root."
                } elseif (Test-PathHasReparsePoint $root $resolved) {
                    $errors += "$id repository-local reference crosses a reparse point."
                } elseif (
                    $asset.status -eq 'active' -and
                    $asset.kind -in @('tool', 'mcp', 'plugin') -and
                    (Test-Path -LiteralPath $resolved -PathType Leaf)
                ) {
                    $actualIntegrity = 'sha256:' + (
                        Get-FileHash -Algorithm SHA256 -LiteralPath $resolved
                    ).Hash.ToLowerInvariant()
                    if ($actualIntegrity -cne [string]$asset.source.integrity) {
                        $errors += "$id SHA-256 integrity evidence does not match."
                    }
                }
            }
        }
        foreach ($field in @(
            'read', 'write', 'destructive', 'open_world', 'private_data',
            'untrusted_content', 'external_communication'
        )) {
            if (
                -not (Test-HasProperty $asset.capabilities $field) -or
                $asset.capabilities.$field -isnot [bool]
            ) {
                $errors += "$id capability $field must be boolean."
            }
        }
        foreach ($field in @('approval_policy', 'isolation', 'disable_procedure')) {
            if ([string]::IsNullOrWhiteSpace([string]$asset.controls.$field)) {
                $errors += "$id controls must define $field."
            }
        }
        if (
            $asset.status -eq 'active' -and
            $asset.risk_tier -in @('high', 'critical') -and
            $asset.controls.approval_policy -eq 'none'
        ) {
            $errors += "$id high-risk active asset lacks approval control."
        }
        $lethalTrifecta = (
            $asset.capabilities.private_data -eq $true -and
            $asset.capabilities.untrusted_content -eq $true -and
            $asset.capabilities.external_communication -eq $true
        )
        if (
            $asset.status -eq 'active' -and $lethalTrifecta -and (
                [string]::IsNullOrWhiteSpace(
                    [string]$asset.controls.source_sink_policy
                ) -or $asset.controls.isolation -eq 'none'
            )
        ) {
            $errors += "$id lethal-trifecta capabilities lack source/sink controls."
        }
        if ($asset.kind -eq 'credential') {
            foreach ($path in @(Find-ForbiddenCredentialField $asset)) {
                $errors += "$id credential contains forbidden field: $path"
            }
            foreach ($field in @('scope', 'audience', 'storage', 'expiry_policy')) {
                if (
                    [string]::IsNullOrWhiteSpace(
                        [string]$asset.credential_policy.$field
                    )
                ) {
                    $errors += "$id credential_policy must define $field."
                }
            }
        }
        $related = @($asset.related_eval_cases)
        if ($related.Count -eq 0) {
            $errors += "$id must link at least one behavior eval case."
        }
        foreach ($caseId in $related) {
            if (-not $caseIds.Contains([string]$caseId)) {
                $errors += "$id references unknown behavior eval case: $caseId"
            }
        }
    }
} catch {
    $errors += "Inventory validation failed: $($_.Exception.Message)"
}

$result = [pscustomobject]@{
    passed = ($errors.Count -eq 0)
    evaluated = $assets.Count
    errors = $errors
}
if ($Json) {
    $result | ConvertTo-Json -Depth 6
} else {
    if ($errors.Count) {
        foreach ($errorMessage in $errors) { "[FAIL] $errorMessage" }
    } else {
        "[PASS] $($assets.Count) governance asset(s) valid"
    }
    "Summary: $(if ($errors.Count) { 'failed' } else { 'passed' })."
}
if ($errors.Count) { exit 1 }
