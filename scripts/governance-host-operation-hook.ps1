[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('codex', 'claude')]
    [string]$HostName,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaPath
)

$ErrorActionPreference = 'Stop'
$maximumInputBytes = 10MB
$maximumLogBytes = 1MB
$lockTimeout = [TimeSpan]::FromSeconds(10)
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Read-BoundedStandardInput {
    param([Parameter(Mandatory)][long]$MaximumBytes)

    $inputStream = [Console]::OpenStandardInput()
    $memory = [IO.MemoryStream]::new()
    $buffer = [byte[]]::new(8192)
    try {
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $MaximumBytes) {
                throw 'Hook input exceeds the allowed size.'
            }
            $memory.Write($buffer, 0, $read)
        }
        return $utf8.GetString($memory.ToArray())
    } finally {
        $memory.Dispose()
    }
}

function Get-RequiredStringProperty {
    param(
        [Parameter(Mandatory)][Text.Json.JsonElement]$Root,
        [Parameter(Mandatory)][string]$Name,
        [int]$MaximumLength = 1024
    )

    $value = $Root.GetProperty($Name)
    if ($value.ValueKind -ne [Text.Json.JsonValueKind]::String) {
        throw "$Name must be a string."
    }
    $text = $value.GetString()
    if (
        [string]::IsNullOrWhiteSpace($text) -or
        $text.Length -gt $MaximumLength
    ) {
        throw "$Name is missing or too long."
    }
    return $text
}

function Write-CanonicalJsonElement {
    param(
        [Parameter(Mandatory)][Text.Json.JsonElement]$Element,
        [Parameter(Mandatory)][Text.Json.Utf8JsonWriter]$Writer
    )

    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $Writer.WriteStartObject()
            foreach ($property in @(
                $Element.EnumerateObject() |
                    Sort-Object -Property Name -CaseSensitive
            )) {
                $Writer.WritePropertyName($property.Name)
                Write-CanonicalJsonElement -Element $property.Value -Writer $Writer
            }
            $Writer.WriteEndObject()
        }
        ([Text.Json.JsonValueKind]::Array) {
            $Writer.WriteStartArray()
            foreach ($item in $Element.EnumerateArray()) {
                Write-CanonicalJsonElement -Element $item -Writer $Writer
            }
            $Writer.WriteEndArray()
        }
        ([Text.Json.JsonValueKind]::String) {
            $Writer.WriteStringValue($Element.GetString())
        }
        ([Text.Json.JsonValueKind]::Number) {
            $Writer.WriteRawValue($Element.GetRawText(), $true)
        }
        ([Text.Json.JsonValueKind]::True) { $Writer.WriteBooleanValue($true) }
        ([Text.Json.JsonValueKind]::False) { $Writer.WriteBooleanValue($false) }
        ([Text.Json.JsonValueKind]::Null) { $Writer.WriteNullValue() }
        default { throw 'Unsupported JSON value in tool_input.' }
    }
}

function Get-JsonElementSha256 {
    param(
        [Parameter(Mandatory)][Text.Json.JsonElement]$Element,
        [Parameter(Mandatory)][string]$Salt
    )

    $memory = [IO.MemoryStream]::new()
    $writer = [Text.Json.Utf8JsonWriter]::new($memory)
    try {
        Write-CanonicalJsonElement -Element $Element -Writer $writer
        $writer.Flush()
        $key = [Security.Cryptography.SHA256]::HashData(
            [Text.UTF8Encoding]::new($false).GetBytes($Salt)
        )
        $hmac = [Security.Cryptography.HMACSHA256]::new($key)
        try {
            return 'sha256:' + [Convert]::ToHexString(
                $hmac.ComputeHash($memory.ToArray())
            ).ToLowerInvariant()
        } finally {
            $hmac.Dispose()
        }
    } finally {
        $writer.Dispose()
        $memory.Dispose()
    }
}

function Get-ArgumentIntegrity {
    <#
    Object-shaped tool_input hashes per top-level key instead of as one
    whole-value digest. This lets PostToolUse validation require every key
    that was present at PreToolUse to still hash identically (tamper
    detection) while tolerating keys a host adds only after the intent was
    recorded -- e.g. AskUserQuestion's "answers", filled in once the user
    responds, which PreToolUse could never have seen. Non-object tool_input
    (or an empty object) falls back to a single whole-value digest, since
    there is no per-key structure to protect selectively.
    #>
    param(
        [Parameter(Mandatory)][Text.Json.JsonElement]$Element,
        [Parameter(Mandatory)][string]$Salt
    )

    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
        return Get-JsonElementSha256 -Element $Element -Salt $Salt
    }
    $properties = @($Element.EnumerateObject())
    if ($properties.Count -eq 0) {
        return Get-JsonElementSha256 -Element $Element -Salt $Salt
    }
    $map = [ordered]@{}
    foreach ($property in $properties) {
        $map[$property.Name] = Get-JsonElementSha256 `
            -Element $property.Value -Salt "$Salt`0$($property.Name)"
    }
    return [pscustomobject]$map
}

function Test-ArgumentIntegrityMatch {
    param(
        [Parameter(Mandatory)]$Stored,
        [Parameter(Mandatory)]$Current,
        [switch]$AllowAdditionalKeys
    )

    $storedIsMap = $Stored -is [Management.Automation.PSCustomObject]
    $currentIsMap = $Current -is [Management.Automation.PSCustomObject]
    if ($storedIsMap -ne $currentIsMap) { return $false }
    if (-not $storedIsMap) {
        return [string]$Stored -ceq [string]$Current
    }
    $storedProperties = @($Stored.PSObject.Properties)
    $currentProperties = @{}
    foreach ($property in $Current.PSObject.Properties) {
        $currentProperties[$property.Name] = [string]$property.Value
    }
    if (
        -not $AllowAdditionalKeys -and
        $storedProperties.Count -ne $currentProperties.Count
    ) {
        return $false
    }
    foreach ($property in $storedProperties) {
        if (-not $currentProperties.ContainsKey($property.Name)) {
            return $false
        }
        if ($currentProperties[$property.Name] -cne [string]$property.Value) {
            return $false
        }
    }
    return $true
}

function Get-PrivateSlug {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Value
    )

    $digest = Get-TextSha256 -Text $Value
    return "$Prefix-$($digest.Substring(7, 32))"
}

function Get-ToolClassification {
    param([Parameter(Mandatory)][string]$ToolName)

    $name = $ToolName.ToLowerInvariant()
    if ($name -match '^(read|glob|grep|list|search_files|find)$') {
        return [pscustomobject][ordered]@{
            effect_kind = 'tool'
            target = 'local-source'
            classification = 'source'
            external = $false
            destructive = $false
        }
    }
    if ($name -match '^(apply_patch|edit|write|notebookedit)$') {
        return [pscustomobject][ordered]@{
            effect_kind = 'durable-write'
            target = 'workspace-file'
            classification = 'action'
            external = $false
            destructive = $true
        }
    }
    if ($name -match '(web|fetch|http|browser|mcp|connector)') {
        return [pscustomobject][ordered]@{
            effect_kind = 'external-action'
            target = 'external-service'
            classification = 'action'
            external = $true
            destructive = $true
        }
    }
    if ($name -match '(bash|shell|powershell|exec|command|terminal)') {
        return [pscustomobject][ordered]@{
            effect_kind = 'external-action'
            target = 'command-environment'
            classification = 'action'
            external = $true
            destructive = $true
        }
    }
    return [pscustomobject][ordered]@{
        effect_kind = 'tool'
        target = 'unclassified-tool'
        classification = 'action'
        external = $true
        destructive = $true
    }
}

function Read-ExistingLog {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Schema
    )

    if ((Get-Item -LiteralPath $Path -Force).Length -gt $maximumLogBytes) {
        throw 'Existing operation log exceeds its size limit.'
    }
    $json = $utf8.GetString([IO.File]::ReadAllBytes($Path))
    if (-not (Test-Json -Json $json -SchemaFile $Schema -ErrorAction Stop)) {
        throw 'Existing operation log does not conform to its schema.'
    }
    return $json | ConvertFrom-Json
}

function Write-DurableLog {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Schema
    )

    $json = $Document | ConvertTo-Json -Depth 32
    if (-not (Test-Json -Json $json -SchemaFile $Schema -ErrorAction Stop)) {
        throw 'Generated operation log does not conform to its schema.'
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    if ($bytes.Length -gt $maximumLogBytes) {
        throw 'Generated operation log exceeds its size limit.'
    }
    $temporary = Join-Path (Split-Path -Parent $Path) (
        ".write-$([Guid]::NewGuid().ToString('N')).tmp"
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
        [IO.File]::Move($temporary, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Enter-LogLock {
    param([Parameter(Mandatory)][string]$Path)

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            return [IO.FileStream]::new(
                $Path,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None,
                1,
                [IO.FileOptions]::WriteThrough
            )
        } catch [IO.IOException] {
            if ($stopwatch.Elapsed -ge $lockTimeout) {
                throw 'Timed out waiting for the operation-log writer.'
            }
            Start-Sleep -Milliseconds 50
        }
    } while ($true)
}

function Test-IntentDocumentIdentity {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$LogId,
        [Parameter(Mandatory)][string]$TaskRef,
        [Parameter(Mandatory)][string]$HostRunId,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$EffectId,
        [Parameter(Mandatory)]$ArgumentIntegrity,
        [Parameter(Mandatory)]$Classification,
        [switch]$AllowAdditionalArgumentKeys
    )

    $records = @($Document.records)
    if ($records.Count -lt 2) { return $false }
    return (
        [int]$Document.schema_version -eq 1 -and
        [string]$Document.log_id -ceq $LogId -and
        [string]$Document.task_ref -ceq $TaskRef -and
        [string]$Document.host_run_id -ceq $HostRunId -and
        [string]$Document.case_id -ceq
            'interrupted-task-reads-checkpoint-before-resume' -and
        [string]$records[0].record_id -ceq 'record-1' -and
        [int]$records[0].sequence -eq 1 -and
        $null -eq $records[0].previous_record_id -and
        [string]$records[0].operation_id -ceq $OperationId -and
        [string]$records[0].type -ceq 'operation-started' -and
        [string]$records[0].operation_kind -ceq 'run' -and
        [string]$records[0].authorization -ceq 'host-hook-policy' -and
        [string]$records[1].record_id -ceq 'record-2' -and
        [int]$records[1].sequence -eq 2 -and
        [string]$records[1].previous_record_id -ceq 'record-1' -and
        [string]$records[1].operation_id -ceq $OperationId -and
        [string]$records[1].type -ceq 'effect-intended' -and
        [string]$records[1].effect_id -ceq $EffectId -and
        [string]$records[1].effect_kind -ceq
            [string]$Classification.effect_kind -and
        [string]$records[1].target -ceq [string]$Classification.target -and
        [string]$records[1].classification -ceq
            [string]$Classification.classification -and
        -not [bool]$records[1].authorized -and
        [string]$records[1].authorization_basis -ceq
            'host-policy-pending' -and
        [bool]$records[1].external -eq [bool]$Classification.external -and
        [bool]$records[1].destructive -eq
            [bool]$Classification.destructive -and
        [string]$records[1].replay -ceq 'never' -and
        (Test-ArgumentIntegrityMatch -Stored $records[1].argument_integrity `
            -Current $ArgumentIntegrity `
            -AllowAdditionalKeys:$AllowAdditionalArgumentKeys)
    )
}

try {
    Import-Module (Join-Path $PSScriptRoot 'lib\GovernanceCommon.psm1') -Force
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

    if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
        $SchemaPath = Join-Path $root (
            'evals\schemas\governance-operation-logs.schema.json'
        )
    }
    $schemaFullPath = [IO.Path]::GetFullPath($SchemaPath)
    if (
        -not (Test-Path -LiteralPath $schemaFullPath -PathType Leaf) -or
        (Get-Item -LiteralPath $schemaFullPath -Force).Length -gt 1MB
    ) {
        throw 'SchemaPath is missing or too large.'
    }
    if (
        (Get-Item -LiteralPath $schemaFullPath -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint
    ) {
        throw 'SchemaPath must not be a reparse point.'
    }

    $payloadText = Read-BoundedStandardInput -MaximumBytes $maximumInputBytes
    $jsonOptions = [Text.Json.JsonDocumentOptions]::new()
    $jsonOptions.MaxDepth = 64
    $payloadDocument = [Text.Json.JsonDocument]::Parse(
        $payloadText, $jsonOptions
    )
    try {
        $payload = $payloadDocument.RootElement
        if ($payload.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
            throw 'Hook payload must be an object.'
        }
        $eventName = Get-RequiredStringProperty -Root $payload `
            -Name 'hook_event_name' -MaximumLength 64
        $sessionId = Get-RequiredStringProperty -Root $payload `
            -Name 'session_id' -MaximumLength 1024
        $toolUseId = Get-RequiredStringProperty -Root $payload `
            -Name 'tool_use_id' -MaximumLength 1024
        $toolName = Get-RequiredStringProperty -Root $payload `
            -Name 'tool_name' -MaximumLength 256
        if ($eventName -cnotin @(
            'PreToolUse', 'PostToolUse', 'PostToolUseFailure'
        )) {
            throw 'Unsupported hook event.'
        }
        if ($HostName -ceq 'codex' -and $eventName -ceq 'PostToolUseFailure') {
            throw 'Codex does not register PostToolUseFailure here.'
        }
        $sessionIdentity = "$HostName`0$sessionId"
        $callIdentity = "$sessionIdentity`0$toolUseId"
        $toolInput = $payload.GetProperty('tool_input')
        $argumentIntegrity = Get-ArgumentIntegrity -Element $toolInput `
            -Salt "$callIdentity`0$toolName"
    } finally {
        $payloadDocument.Dispose()
    }

    $sessionSlug = Get-PrivateSlug -Prefix 'session' -Value $sessionIdentity
    $callSlug = Get-PrivateSlug -Prefix 'call' -Value $callIdentity
    $logId = "$HostName-$callSlug"
    $operationId = "operation-$callSlug"
    $effectId = "effect-$callSlug"
    $classification = Get-ToolClassification -ToolName $toolName
    $taskRef = "host-hook-$sessionSlug"
    $hostRunId = "$HostName-$sessionSlug"

    $logDirectory = [IO.Path]::GetFullPath((Join-Path $root (
        ".local\governance\operation-hooks\$HostName"
    )))
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $logDirectory.StartsWith(
        $rootPrefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Operation-log directory resolves outside ProjectRoot.'
    }
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $logDirectory) {
        throw 'Operation-log directory must not cross a reparse point.'
    }
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    if (Test-PathHasReparsePoint -Root $root -ResolvedPath $logDirectory) {
        throw 'Operation-log directory must not cross a reparse point.'
    }
    $logPath = Join-Path $logDirectory "$logId.json"
    $lockPath = "$logPath.lock"
    foreach ($candidate in @($logPath, $lockPath)) {
        if (
            (Test-Path -LiteralPath $candidate) -and
            (Test-PathHasReparsePoint -Root $root -ResolvedPath $candidate)
        ) {
            throw 'Operation-log paths must not cross a reparse point.'
        }
    }

    $lock = Enter-LogLock -Path $lockPath
    try {
        $existing = if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            Read-ExistingLog -Path $logPath -Schema $schemaFullPath
        } else { $null }

        if ($eventName -ceq 'PreToolUse') {
            if ($null -ne $existing) {
                $records = @($existing.records)
                if (
                    $records.Count -eq 2 -and
                    (Test-IntentDocumentIdentity -Document $existing `
                        -LogId $logId -TaskRef $taskRef `
                        -HostRunId $hostRunId -OperationId $operationId `
                        -EffectId $effectId `
                        -ArgumentIntegrity $argumentIntegrity `
                        -Classification $classification) -and
                    [string]$existing.runner_state.status -ceq
                        'requires-reconciliation' -and
                    [string]$existing.runner_state.pending_effect_id -ceq
                        $effectId -and
                    [int]$existing.runner_state.last_sequence -eq 2
                ) {
                    exit 0
                }
                throw 'PreToolUse identity conflicts with durable evidence.'
            }
            $now = [DateTimeOffset]::UtcNow.ToString('o')
            $document = [pscustomobject][ordered]@{
                schema_version = 1
                log_id = $logId
                task_ref = $taskRef
                host_run_id = $hostRunId
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
                started_at = $now
                runner_state = [pscustomobject][ordered]@{
                    status = 'requires-reconciliation'
                    pending_effect_id = $effectId
                    last_sequence = 2
                }
                records = @(
                    [pscustomobject][ordered]@{
                        record_id = 'record-1'
                        sequence = 1
                        previous_record_id = $null
                        occurred_at = $now
                        operation_id = $operationId
                        type = 'operation-started'
                        operation_kind = 'run'
                        authorization = 'host-hook-policy'
                    }
                    [pscustomobject][ordered]@{
                        record_id = 'record-2'
                        sequence = 2
                        previous_record_id = 'record-1'
                        occurred_at = $now
                        operation_id = $operationId
                        type = 'effect-intended'
                        effect_id = $effectId
                        effect_kind = $classification.effect_kind
                        target = $classification.target
                        classification = $classification.classification
                        authorized = $false
                        authorization_basis = 'host-policy-pending'
                        external = $classification.external
                        destructive = $classification.destructive
                        replay = 'never'
                        argument_integrity = $argumentIntegrity
                    }
                )
            }
            Write-DurableLog -Document $document -Path $logPath `
                -Schema $schemaFullPath
            exit 0
        }

        if ($null -eq $existing) {
            throw 'Post event has no durable PreToolUse intent.'
        }
        $records = @($existing.records)
        if (-not (Test-IntentDocumentIdentity -Document $existing `
            -LogId $logId -TaskRef $taskRef -HostRunId $hostRunId `
            -OperationId $operationId -EffectId $effectId `
            -ArgumentIntegrity $argumentIntegrity `
            -Classification $classification `
            -AllowAdditionalArgumentKeys)) {
            throw 'Post event identity does not match its durable intent.'
        }
        $resultValue = if ($eventName -ceq 'PostToolUse') {
            'succeeded'
        } else { 'failed' }
        $evidenceCode = if ($resultValue -ceq 'succeeded') {
            "$HostName-tool-succeeded"
        } else { "$HostName-tool-failed" }
        if ($records.Count -eq 3) {
            $expectedRunnerStatus = if ($resultValue -ceq 'succeeded') {
                'open'
            } else { 'requires-reconciliation' }
            $pendingEffectMatches = if ($resultValue -ceq 'succeeded') {
                $null -eq $existing.runner_state.pending_effect_id
            } else {
                [string]$existing.runner_state.pending_effect_id -ceq $effectId
            }
            if (
                [string]$records[2].record_id -ceq 'record-3' -and
                [int]$records[2].sequence -eq 3 -and
                [string]$records[2].previous_record_id -ceq 'record-2' -and
                [string]$records[2].operation_id -ceq $operationId -and
                [string]$records[2].type -ceq 'effect-result' -and
                [string]$records[2].effect_id -ceq $effectId -and
                [string]$records[2].result -ceq $resultValue -and
                [string]$records[2].evidence_code -ceq $evidenceCode -and
                [string]$records[2].authorization_evidence -ceq
                    'host-permitted' -and
                [string]$existing.runner_state.status -ceq
                    $expectedRunnerStatus -and
                $pendingEffectMatches -and
                [int]$existing.runner_state.last_sequence -eq 3
            ) {
                exit 0
            }
            throw 'Post event conflicts with its durable result.'
        }
        if ($records.Count -ne 2) {
            throw 'Post event found an invalid durable record count.'
        }
        if (
            [string]$existing.runner_state.status -cne
                'requires-reconciliation' -or
            [string]$existing.runner_state.pending_effect_id -cne $effectId -or
            [int]$existing.runner_state.last_sequence -ne 2
        ) {
            throw 'Post event found a conflicting durable runner state.'
        }
        $resultTimestamp = [DateTimeOffset]::UtcNow
        $intentTimestamp = [DateTimeOffset]$records[1].occurred_at
        if ($resultTimestamp -lt $intentTimestamp) {
            $resultTimestamp = $intentTimestamp
        }
        $resultTime = $resultTimestamp.ToString('o')
        $existing.records = @($records) + [pscustomobject][ordered]@{
            record_id = 'record-3'
            sequence = 3
            previous_record_id = 'record-2'
            occurred_at = $resultTime
            operation_id = $operationId
            type = 'effect-result'
            effect_id = $effectId
            result = $resultValue
            evidence_code = $evidenceCode
            authorization_evidence = 'host-permitted'
        }
        $existing.runner_state.status = if ($resultValue -ceq 'succeeded') {
            'open'
        } else { 'requires-reconciliation' }
        $existing.runner_state.pending_effect_id = if (
            $resultValue -ceq 'succeeded'
        ) { $null } else { $effectId }
        $existing.runner_state.last_sequence = 3
        Write-DurableLog -Document $existing -Path $logPath `
            -Schema $schemaFullPath
    } finally {
        $lock.Dispose()
    }
    exit 0
} catch {
    try {
        $diagnosticDirectory = if ($logDirectory) {
            $logDirectory
        } else {
            Join-Path ([IO.Path]::GetFullPath($ProjectRoot)) (
                ".local\governance\operation-hooks\$HostName"
            )
        }
        New-Item -ItemType Directory -Path $diagnosticDirectory -Force |
            Out-Null
        $diagnosticName = if ($logId) { "$logId.error.log" } else {
            'unidentified.error.log'
        }
        $diagnosticPath = Join-Path $diagnosticDirectory $diagnosticName
        if (
            (Test-Path -LiteralPath $diagnosticPath -PathType Leaf) -and
            (Get-Item -LiteralPath $diagnosticPath -Force).Length -gt 200KB
        ) {
            Remove-Item -LiteralPath $diagnosticPath -Force
        }
        $diagnosticLine = (
            "$([DateTimeOffset]::UtcNow.ToString('o')) " +
            "$($_.Exception.GetType().FullName): $($_.Exception.Message)`n"
        )
        [IO.File]::AppendAllText(
            $diagnosticPath, $diagnosticLine, $utf8
        )
    } catch {
        # Diagnostic logging is best-effort only; never let it mask the
        # original rejection below.
    }
    [Console]::Error.WriteLine(
        'projectD governance hook rejected the host event.'
    )
    exit 2
}
