[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reconciler = Join-Path $core 'scripts\governance-reconcile-orphaned-logs.ps1'
$schema = Join-Path $core 'evals\schemas\governance-operation-logs.schema.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "governance-reconcile-contract-$PID-$([Guid]::NewGuid().ToString('N'))"
)
$logDirectory = Join-Path $tempRoot '.local\governance\operation-hooks\codex'
$oldTime = '2026-09-01T00:00:00Z'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-OrphanedLog {
    param(
        [Parameter(Mandatory)][ValidateSet('source', 'action')]
        [string]$Classification
    )

    $effectKind = if ($Classification -ceq 'source') { 'tool' } else { 'durable-write' }
    return [pscustomobject][ordered]@{
        schema_version = 1
        log_id = "$Classification-log"
        task_ref = "$Classification-task"
        host_run_id = "$Classification-run"
        case_id = 'interrupted-task-reads-checkpoint-before-resume'
        privacy = [pscustomobject][ordered]@{
            content_mode = 'metadata-only'
            redaction_status = 'verified'
            contains_raw_prompt = $false
            contains_chain_of_thought = $false
            contains_secret_values = $false
            contains_private_data = $false
            contains_tool_arguments = $false
            contains_tool_output = $false
        }
        started_at = $oldTime
        runner_state = [pscustomobject][ordered]@{
            status = 'requires-reconciliation'
            pending_effect_id = "$Classification-effect"
            last_sequence = 2
        }
        records = @(
            [pscustomobject][ordered]@{
                record_id = 'record-1'
                sequence = 1
                previous_record_id = $null
                occurred_at = $oldTime
                operation_id = "$Classification-operation"
                type = 'operation-started'
                operation_kind = 'run'
                authorization = 'host-hook-policy'
            }
            [pscustomobject][ordered]@{
                record_id = 'record-2'
                sequence = 2
                previous_record_id = 'record-1'
                occurred_at = $oldTime
                operation_id = "$Classification-operation"
                type = 'effect-intended'
                effect_id = "$Classification-effect"
                effect_kind = $effectKind
                target = "$Classification-target"
                classification = $Classification
                authorized = $false
                authorization_basis = 'host-policy-pending'
                external = $false
                destructive = $false
                replay = 'never'
                argument_integrity = 'sha256:' + ('a' * 64)
            }
        )
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Path
    )
    $json = $Document | ConvertTo-Json -Depth 20
    Assert-True (Test-Json -Json $json -SchemaFile $schema -ErrorAction Stop) (
        "Fixture must conform to the operation-log schema: $Path"
    )
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

try {
    [void](New-Item -ItemType Directory -Path $logDirectory -Force)
    $sourcePath = Join-Path $logDirectory 'source.json'
    $actionPath = Join-Path $logDirectory 'action.json'
    Write-Log -Document (New-OrphanedLog -Classification source) -Path $sourcePath
    Write-Log -Document (New-OrphanedLog -Classification action) -Path $actionPath

    $output = @(& $reconciler `
        -HostName codex `
        -ProjectRoot $tempRoot `
        -SchemaPath $schema `
        -MinimumAgeSeconds 0 `
        -Outcome aborted `
        -SourceOnly)

    $source = Get-Content -Raw -LiteralPath $sourcePath | ConvertFrom-Json
    $action = Get-Content -Raw -LiteralPath $actionPath | ConvertFrom-Json

    Assert-True (@($source.records).Count -eq 3) (
        'SourceOnly must append one terminal record to a Source-classified orphan.'
    )
    Assert-True ([string]$source.records[2].outcome -ceq 'aborted') (
        'The reconciled Source operation must use the requested outcome.'
    )
    Assert-True ([string]$source.runner_state.status -ceq 'aborted') (
        'The reconciled Source runner must become terminal.'
    )
    Assert-True ($null -eq $source.runner_state.pending_effect_id) (
        'The reconciled Source runner must clear its pending effect.'
    )
    Assert-True (@($action.records).Count -eq 2) (
        'SourceOnly must not append a record to an Action-classified orphan.'
    )
    Assert-True (
        [string]$action.runner_state.status -ceq 'requires-reconciliation'
    ) 'SourceOnly must leave the filtered Action runner pending.'
    Assert-True (
        @($output | Where-Object {
            $_ -ceq 'Done. Reconciled: 1. Skipped: 0. Filtered: 1. Scanned: 2.'
        }).Count -eq 1
    ) 'The summary must report one reconciled and one filtered log.'
    Assert-True (
        Test-Json -Json (Get-Content -Raw -LiteralPath $sourcePath) `
            -SchemaFile $schema -ErrorAction Stop
    ) 'The reconciled Source log must remain schema-valid.'

    Write-Output 'Governance orphan reconciliation contract passed.'
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
