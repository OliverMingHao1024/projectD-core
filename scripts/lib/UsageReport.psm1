Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'GovernanceCommon.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'UsageExportGate.psm1') -Force

$script:utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:metricNames = @(
    'input_tokens', 'cached_input_tokens', 'output_tokens',
    'reasoning_tokens', 'cache_creation_tokens', 'estimated_cost_usd'
)

function Get-UsageReportSchemaPath {
    param([Parameter(Mandatory)][string]$SchemaFileName)
    $resolved = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..\..\evals\schemas\$SchemaFileName")
    )
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Canonical schema is missing: $SchemaFileName"
    }
    return $resolved
}

function Assert-UsageReportSchemaValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaFileName,
        [Parameter(Mandatory)][string]$Label
    )
    $schemaPath = Get-UsageReportSchemaPath -SchemaFileName $SchemaFileName
    try {
        $json = $Value | ConvertTo-Json -Depth 32
        $valid = Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop
        if (-not $valid) { throw 'JSON Schema validation returned false.' }
    } catch {
        throw "$Label does not conform to its canonical schema."
    }
}

function ConvertTo-UsageReportUtcTimestamp {
    param([Parameter(Mandatory)]$Value)
    return ([DateTimeOffset]$Value).ToUniversalTime()
}

function Get-ProjectDUsageDateBucket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$OccurredAt,
        [Parameter(Mandatory)][ValidateSet('day', 'week')][string]$GroupBy
    )

    $moment = (ConvertTo-UsageReportUtcTimestamp $OccurredAt).UtcDateTime
    $dayStart = [DateTime]::new(
        $moment.Year, $moment.Month, $moment.Day, 0, 0, 0, [DateTimeKind]::Utc
    )
    if ($GroupBy -ceq 'day') {
        $start = $dayStart
        $end = $dayStart.AddDays(1)
    } else {
        $daysSinceMonday = ([int]$dayStart.DayOfWeek + 6) % 7
        $start = $dayStart.AddDays(-$daysSinceMonday)
        $end = $start.AddDays(7)
    }
    return [pscustomobject][ordered]@{
        start = ([DateTimeOffset]$start).ToString('o')
        end = ([DateTimeOffset]$end).ToString('o')
    }
}

function Get-UsageReportRowKey {
    param([Parameter(Mandatory)]$Row)
    return (
        [string]$Row.period.start + "`0" + [string]$Row.period.end + "`0" +
        [string]$Row.provider + "`0" + [string]$Row.alias + "`0" +
        [string]$Row.device_id + "`0" + [string]$Row.environment + "`0" +
        [string]$Row.model + "`0" + [string]$Row.local_context
    )
}

function Get-UsageReportLedgerLocalContextLabel {
    param([Parameter(Mandatory)]$Event)
    if ($Event.PSObject.Properties.Name -cnotcontains 'local_context') {
        return $null
    }
    if ($null -eq $Event.local_context) { return $null }
    return [string]$Event.local_context.label
}

function New-ProjectDUsageReportRowsFromLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Records,
        [Parameter(Mandatory)][ValidateSet('day', 'week')][string]$GroupBy
    )

    $buckets = [ordered]@{}
    foreach ($record in $Records) {
        $event = $record.event
        if ([string]$event.identity.verification_status -cne 'verified') {
            throw (
                'A ledger record with an unverified identity cannot enter ' +
                'a report.'
            )
        }
        $bucket = Get-ProjectDUsageDateBucket `
            -OccurredAt $event.occurred_at -GroupBy $GroupBy
        $model = if ([string]$event.model.status -ceq 'observed') {
            [string]$event.model.value
        } else { 'unknown' }
        $row = [pscustomobject][ordered]@{
            period = $bucket
            provider = [string]$event.provider
            alias = [string]$event.identity.account_alias
            device_id = [string]$event.identity.device_id
            environment = [string]$event.identity.environment
            model = $model
            local_context = Get-UsageReportLedgerLocalContextLabel $event
        }
        $key = Get-UsageReportRowKey $row
        if (-not $buckets.Contains($key)) {
            $sums = [ordered]@{}
            foreach ($name in $script:metricNames) { $sums[$name] = $null }
            $buckets[$key] = [pscustomobject][ordered]@{
                row = $row
                run_count = 0
                sums = $sums
            }
        }
        $entry = $buckets[$key]
        $entry.run_count++
        foreach ($name in $script:metricNames) {
            $metric = $event.usage.$name
            if ($null -ne $metric -and [string]$metric.status -ceq 'observed') {
                $current = $entry.sums[$name]
                $entry.sums[$name] = (
                    [decimal]($null -eq $current ? 0 : $current) +
                    [decimal]$metric.value
                )
            }
        }
    }
    return @(Complete-ProjectDUsageReportRows -Buckets $buckets)
}

function New-ProjectDUsageReportRowsFromMergeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)

    $buckets = [ordered]@{}
    foreach ($total in @($State.totals)) {
        $row = [pscustomobject][ordered]@{
            period = [pscustomobject][ordered]@{
                start = (ConvertTo-UsageReportUtcTimestamp $total.period.start).ToString('o')
                end = (ConvertTo-UsageReportUtcTimestamp $total.period.end).ToString('o')
            }
            provider = [string]$total.provider
            alias = [string]$total.alias
            device_id = [string]$total.device_id
            environment = [string]$total.environment
            model = [string]$total.model
            # Merge-state totals never carry local_context: it is dropped
            # by construction before an event crosses the export gate
            # (see ConvertTo-ProjectDUsageExportBatch), so no merged row
            # can ever legitimately have one.
            local_context = $null
        }
        $key = Get-UsageReportRowKey $row
        if ($buckets.Contains($key)) {
            throw 'Merge state totals must already be unique per group key.'
        }
        $sums = [ordered]@{}
        foreach ($name in $script:metricNames) {
            $metric = $total.$name
            $sums[$name] = if (
                $null -ne $metric -and [string]$metric.status -ceq 'observed'
            ) { [decimal]$metric.value } else { $null }
        }
        $buckets[$key] = [pscustomobject][ordered]@{
            row = $row
            run_count = [long]$total.run_count
            sums = $sums
        }
    }
    return @(Complete-ProjectDUsageReportRows -Buckets $buckets)
}

function Complete-ProjectDUsageReportRows {
    param([Parameter(Mandatory)]$Buckets)

    return @(
        $Buckets.Values |
            Sort-Object -Property @(
                @{ Expression = { $_.row.period.start } },
                @{ Expression = { $_.row.provider } },
                @{ Expression = { $_.row.alias } },
                @{ Expression = { $_.row.device_id } },
                @{ Expression = { $_.row.environment } },
                @{ Expression = { $_.row.model } }
            ) |
            ForEach-Object {
                $entry = $_
                $out = [ordered]@{
                    period = $entry.row.period
                    provider = $entry.row.provider
                    alias = $entry.row.alias
                    device_id = $entry.row.device_id
                    environment = $entry.row.environment
                    model = $entry.row.model
                    local_context = $entry.row.local_context
                    run_count = $entry.run_count
                }
                foreach ($name in $script:metricNames) {
                    $value = $entry.sums[$name]
                    $out[$name] = if ($null -eq $value) {
                        [pscustomobject][ordered]@{
                            status = 'unavailable'; value = $null
                        }
                    } else {
                        [pscustomobject][ordered]@{
                            status = 'observed'; value = $value
                        }
                    }
                }
                [pscustomobject]$out
            }
    )
}

function Get-ProjectDUsageIdentityWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Diagnostics,
        [Parameter(Mandatory)][ValidateSet('day', 'week')][string]$GroupBy
    )

    $groups = [ordered]@{}
    foreach ($diagnostic in $Diagnostics) {
        $bucket = Get-ProjectDUsageDateBucket `
            -OccurredAt $diagnostic.occurred_at -GroupBy $GroupBy
        $type = if ([string]$diagnostic.verification_status -ceq 'mismatch') {
            'account_mismatch'
        } else { 'unknown_identity' }
        $key = (
            $type + "`0" + [string]$bucket.start + "`0" +
            [string]$diagnostic.provider + "`0" +
            [string]$diagnostic.device_id + "`0" +
            [string]$diagnostic.environment
        )
        if (-not $groups.Contains($key)) {
            $groups[$key] = [pscustomobject][ordered]@{
                type = $type
                period = $bucket
                provider = [string]$diagnostic.provider
                device_id = [string]$diagnostic.device_id
                environment = [string]$diagnostic.environment
                count = 0
            }
        }
        $groups[$key].count++
    }
    return @(
        $groups.Values | ForEach-Object {
            $g = $_
            [pscustomobject][ordered]@{
                type = $g.type
                message = (
                    "$($g.count) $($g.type) event(s) for provider " +
                    "$($g.provider) on device $($g.device_id) " +
                    "($($g.environment))."
                )
                provider = $g.provider
                device_id = $g.device_id
                environment = $g.environment
                period = $g.period
                metric = $null
                observed_value = $null
                baseline_value = $null
                count = $g.count
            }
        }
    )
}

function Get-ProjectDUsageDataGapWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Rows,
        [Parameter(Mandatory)][string]$PeriodStart,
        [Parameter(Mandatory)][string]$PeriodEnd,
        [Parameter(Mandatory)][ValidateSet('day', 'week')][string]$GroupBy
    )

    $covered = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($row in $Rows) { [void]$covered.Add([string]$row.period.start) }

    $start = (ConvertTo-UsageReportUtcTimestamp $PeriodStart).UtcDateTime
    $end = (ConvertTo-UsageReportUtcTimestamp $PeriodEnd).UtcDateTime
    $step = if ($GroupBy -ceq 'day') { [TimeSpan]::FromDays(1) } else {
        [TimeSpan]::FromDays(7)
    }
    $warnings = [Collections.Generic.List[object]]::new()
    $cursor = $start
    while ($cursor -lt $end) {
        $bucket = Get-ProjectDUsageDateBucket -OccurredAt $cursor -GroupBy $GroupBy
        if (-not $covered.Contains([string]$bucket.start)) {
            $warnings.Add([pscustomobject][ordered]@{
                type = 'data_gap'
                message = "No usage rows for the $GroupBy starting $($bucket.start)."
                provider = $null
                device_id = $null
                environment = $null
                period = $bucket
                metric = $null
                observed_value = $null
                baseline_value = $null
                count = $null
            })
        }
        $cursor = $cursor.Add($step)
    }
    return @($warnings)
}

function Get-ProjectDUsageAnomalyWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Rows,
        [Collections.IDictionary]$BaselinePerRun = @{}
    )

    $warnings = [Collections.Generic.List[object]]::new()
    foreach ($row in $Rows) {
        foreach ($name in @($BaselinePerRun.Keys)) {
            if ($name -cnotin $script:metricNames) {
                throw "Unsupported baseline metric: $name"
            }
            $metric = $row.$name
            if ([string]$metric.status -cne 'observed') { continue }
            $baseline = [decimal]$BaselinePerRun[$name]
            $observedPerRun = [decimal]$metric.value / [decimal]$row.run_count
            if ($observedPerRun -gt $baseline) {
                $warnings.Add([pscustomobject][ordered]@{
                    type = 'anomalous_usage'
                    message = (
                        "$name averaged $observedPerRun per run for " +
                        "$($row.alias)/$($row.provider)/$($row.model) on " +
                        "$($row.device_id), above the $baseline baseline."
                    )
                    provider = [string]$row.provider
                    device_id = [string]$row.device_id
                    environment = [string]$row.environment
                    period = $row.period
                    metric = $name
                    observed_value = [double]$observedPerRun
                    baseline_value = [double]$baseline
                    count = $null
                })
            }
        }
    }
    return @($warnings)
}

function New-ProjectDUsageReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('local', 'merged')][string]$Mode,
        [Parameter(Mandatory)][ValidateSet('day', 'week')][string]$GroupBy,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Rows,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Warnings,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$QuotaSnapshots,
        [Parameter(Mandatory)][string]$PeriodStart,
        [Parameter(Mandatory)][string]$PeriodEnd,
        [Parameter(Mandatory)][string]$GeneratedAt
    )

    $report = [pscustomobject][ordered]@{
        schema_version = 1
        mode = $Mode
        generated_at = $GeneratedAt
        period = [pscustomobject][ordered]@{
            start = $PeriodStart
            end = $PeriodEnd
        }
        group_by = $GroupBy
        rows = $Rows
        quota_snapshots = $QuotaSnapshots
        warnings = $Warnings
    }
    Assert-UsageReportSchemaValue `
        -Value $report `
        -SchemaFileName 'usage-report.schema.json' `
        -Label 'Usage report'

    # The content canary exists to catch export-unsafe values (emails,
    # filesystem paths, repo URLs) reaching an artifact meant to leave
    # this machine. local_context.label is the one field explicitly
    # exempt from that: it is designed to carry exactly this kind of
    # local project/task text (see localContext in
    # usage-events.schema.json), and it never appears outside a
    # local-mode report -- New-ProjectDUsageReportRowsFromMergeState
    # always sets it to $null. Redact it before the scan so a legitimate
    # local label (a folder name containing "workspace", an "@" in a
    # thread title, etc.) cannot make report generation fail closed.
    $canaryRows = @($Rows | ForEach-Object {
        $clone = $_.PSObject.Copy()
        if ($null -ne $clone.local_context) { $clone.local_context = 'redacted' }
        $clone
    })
    $canaryReport = [pscustomobject][ordered]@{
        schema_version = $report.schema_version
        mode = $report.mode
        generated_at = $report.generated_at
        period = $report.period
        group_by = $report.group_by
        rows = $canaryRows
        quota_snapshots = $report.quota_snapshots
        warnings = $report.warnings
    }
    $serialized = $canaryReport | ConvertTo-Json -Depth 32
    if (-not (Test-ProjectDUsageExportContentSafe -Text $serialized)) {
        throw (
            'Usage report failed the content canary scan; refusing to ' +
            'produce a report that may contain identifying content.'
        )
    }
    return $report
}

Export-ModuleMember -Function @(
    'Get-ProjectDUsageDateBucket',
    'New-ProjectDUsageReportRowsFromLedger',
    'New-ProjectDUsageReportRowsFromMergeState',
    'Get-ProjectDUsageIdentityWarnings',
    'Get-ProjectDUsageDataGapWarnings',
    'Get-ProjectDUsageAnomalyWarnings',
    'New-ProjectDUsageReport'
)
