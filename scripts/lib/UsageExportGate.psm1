Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'GovernanceCommon.psm1') -Force

$script:utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:schemaRoot = Join-Path $PSScriptRoot '..\..\evals\schemas'

function Get-UsageExportSchemaPath {
    param([Parameter(Mandatory)][string]$SchemaFileName)
    $resolved = Join-Path $script:schemaRoot $SchemaFileName
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Canonical schema is missing: $SchemaFileName"
    }
    return $resolved
}

function Assert-UsageExportSchemaValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaFileName,
        [Parameter(Mandatory)][string]$Label
    )
    $schemaPath = Get-UsageExportSchemaPath -SchemaFileName $SchemaFileName
    try {
        $json = $Value | ConvertTo-Json -Depth 32
        $valid = Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop
        if (-not $valid) { throw 'JSON Schema validation returned false.' }
    } catch {
        throw "$Label does not conform to its canonical schema."
    }
}

function Get-ProjectDUsageExportCanaryPatterns {
    <#
    Defense-in-depth content scan applied to the fully-serialized export
    batch. The primary defense is structural: the batch schema only
    allows a closed set of enum/pattern-constrained fields (alias,
    provider, model, numeric metrics, version strings), so free-text
    values such as email addresses, local filesystem paths, or
    repository URLs cannot conform to those patterns in the first
    place. These patterns exist to fail closed if that structural
    defense is ever bypassed or weakened.
    #>
    return @(Get-SensitiveValuePatterns) + @(
        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
        '(?i)[A-Za-z]:\\\\',
        '(?i)/(?:home|Users)/',
        '(?i)\b(?:github|gitlab|bitbucket)\.com\b',
        '(?i)\.git\b',
        '(?i)\bworkspaces?\b'
    )
}

function Test-ProjectDUsageExportContentSafe {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    foreach ($pattern in Get-ProjectDUsageExportCanaryPatterns) {
        if ($Text -match $pattern) { return $false }
    }
    return $true
}

function Read-ProjectDUsageExportPolicy {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            schema_version = 1
            export_allowed = $false
            policy_version = 'local-only-default'
        }
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt 4KB) {
        throw 'Usage export policy exceeds its size limit.'
    }
    try {
        $json = $script:utf8.GetString([IO.File]::ReadAllBytes($Path))
        $policy = $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw 'Usage export policy is not valid UTF-8 JSON.'
    }
    Assert-UsageExportSchemaValue `
        -Value $policy `
        -SchemaFileName 'usage-export-policy.schema.json' `
        -Label 'Usage export policy'
    return $policy
}

function Test-ProjectDUsageExportAllowed {
    param([Parameter(Mandatory)]$Policy)
    return [bool]$Policy.export_allowed
}

function ConvertTo-ProjectDUsageExportBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Records,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][string]$PeriodStart,
        [Parameter(Mandatory)][string]$PeriodEnd,
        [Parameter(Mandatory)][string]$SourceVersion,
        [string]$RedactionVersion = 'v1',
        [Parameter(Mandatory)][string]$GeneratedAt
    )

    if (-not (Test-ProjectDUsageExportAllowed -Policy $Policy)) {
        throw (
            'Usage export is not allowed by local policy; this device ' +
            'defaults to local-only.'
        )
    }
    if (
        $SourceVersion -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or
        [string]$RedactionVersion -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
    ) {
        throw 'SourceVersion or RedactionVersion is invalid.'
    }

    $groups = [ordered]@{}
    foreach ($record in $Records) {
        $event = $record.event
        if ([string]$event.identity.verification_status -cne 'verified') {
            throw (
                'A record with an unverified identity cannot enter an ' +
                'export batch.'
            )
        }
        $alias = [string]$event.identity.account_alias
        if ($alias -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw 'A record has an alias outside the exportable pattern.'
        }
        $provider = [string]$event.provider
        if ($provider -cnotin @('codex', 'claude')) {
            throw 'A record has an unsupported provider.'
        }
        $model = if ([string]$event.model.status -ceq 'observed') {
            [string]$event.model.value
        } else { 'unknown' }
        if ($model -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$') {
            throw 'A record has a model value outside the exportable pattern.'
        }
        $key = "$alias`0$provider`0$model"
        if (-not $groups.Contains($key)) {
            $groups[$key] = [pscustomobject][ordered]@{
                alias = $alias
                provider = $provider
                model = $model
                run_count = 0
                sums = [ordered]@{
                    input_tokens = $null
                    cached_input_tokens = $null
                    output_tokens = $null
                    reasoning_tokens = $null
                    cache_creation_tokens = $null
                    estimated_cost_usd = $null
                }
            }
        }
        $bucket = $groups[$key]
        $bucket.run_count++
        foreach ($name in @(
            'input_tokens', 'cached_input_tokens', 'output_tokens',
            'reasoning_tokens', 'cache_creation_tokens', 'estimated_cost_usd'
        )) {
            $metric = $event.usage.$name
            if ($null -ne $metric -and [string]$metric.status -ceq 'observed') {
                $current = $bucket.sums[$name]
                $bucket.sums[$name] = (
                    [decimal]([string]::IsNullOrEmpty($current) ? 0 : $current) +
                    [decimal]$metric.value
                )
            }
        }
    }

    $rows = @(
        foreach ($bucket in $groups.Values) {
            $row = [ordered]@{
                alias = $bucket.alias
                provider = $bucket.provider
                model = $bucket.model
                run_count = $bucket.run_count
            }
            foreach ($name in @(
                'input_tokens', 'cached_input_tokens', 'output_tokens',
                'reasoning_tokens', 'cache_creation_tokens', 'estimated_cost_usd'
            )) {
                $value = $bucket.sums[$name]
                $row[$name] = if ($null -eq $value) {
                    [pscustomobject][ordered]@{ status = 'unavailable'; value = $null }
                } else {
                    [pscustomobject][ordered]@{ status = 'observed'; value = $value }
                }
            }
            [pscustomobject]$row
        }
    )

    $batch = [pscustomobject][ordered]@{
        schema_version = 1
        policy_version = [string]$Policy.policy_version
        redaction_version = $RedactionVersion
        source_version = $SourceVersion
        generated_at = $GeneratedAt
        period = [pscustomobject][ordered]@{
            start = $PeriodStart
            end = $PeriodEnd
        }
        rows = $rows
    }
    Assert-UsageExportSchemaValue `
        -Value $batch `
        -SchemaFileName 'usage-export-batch.schema.json' `
        -Label 'Usage export batch'
    $serialized = $batch | ConvertTo-Json -Depth 32
    if (-not (Test-ProjectDUsageExportContentSafe -Text $serialized)) {
        throw (
            'Usage export batch failed the source-side content canary scan; ' +
            'quarantining instead of exporting.'
        )
    }
    return $batch
}

function Write-ProjectDUsageExportQuarantine {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Reason
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $quarantineRoot = [IO.Path]::GetFullPath((
        Join-Path $root '.local\usage\export\quarantine'
    ))
    $localRoot = [IO.Path]::GetFullPath((Join-Path $root '.local'))
    if (-not $quarantineRoot.StartsWith(
        $localRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Quarantine path resolves outside ProjectRoot/.local.'
    }
    New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null
    $record = [pscustomobject][ordered]@{
        schema_version = 1
        quarantined_at = [DateTimeOffset]::UtcNow.ToString('o')
        reason = $Reason
    }
    $id = [Guid]::NewGuid().ToString('N')
    $path = Join-Path $quarantineRoot "$id.json"
    $record | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $path -Encoding utf8 -NoNewline
    return $path
}

Export-ModuleMember -Function @(
    'Get-ProjectDUsageExportCanaryPatterns',
    'Test-ProjectDUsageExportContentSafe',
    'Read-ProjectDUsageExportPolicy',
    'Test-ProjectDUsageExportAllowed',
    'ConvertTo-ProjectDUsageExportBatch',
    'Write-ProjectDUsageExportQuarantine'
)
