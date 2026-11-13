# Part of ProjectD.GovernanceWiring.psm1; dot-sourced into that module.
# Read-only inspection of current state and plan building.

function Get-ManagedBlockInspection {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    if (-not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) {
        return @{ State = 'Missing'; Message = 'Target file is missing.' }
    }
    $content = [IO.File]::ReadAllText($Resource.Path)
    $startCount = ([regex]::Matches(
        $content,
        [regex]::Escape($Resource.BlockStart)
    )).Count
    $endCount = ([regex]::Matches(
        $content,
        [regex]::Escape($Resource.BlockEnd)
    )).Count
    if ($startCount -eq 0 -and $endCount -eq 0) {
        return @{ State = 'Missing'; Message = 'Managed block is absent.' }
    }
    if ($startCount -ne 1 -or $endCount -ne 1) {
        return @{
            State = 'Conflict'
            Message = 'Managed block markers are incomplete or duplicated.'
        }
    }
    $pattern = [regex]::new(
        [regex]::Escape($Resource.BlockStart) +
            '.*?' +
            [regex]::Escape($Resource.BlockEnd),
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $matches = $pattern.Matches($content)
    if ($matches.Count -ne 1) {
        return @{
            State = 'Conflict'
            Message = 'Managed block marker ordering is invalid.'
        }
    }
    if (
        (Normalize-WiringText $matches[0].Value) -eq
        (Normalize-WiringText $Resource.Content)
    ) {
        return @{ State = 'Compliant'; Message = 'Managed block matches.' }
    }
    $diff = Get-TextDiff `
        -Old (Normalize-WiringText $matches[0].Value) `
        -New (Normalize-WiringText $Resource.Content) `
        -Label ([IO.Path]::GetFileName($Resource.Path))
    return @{
        State = 'Drift'
        Message = 'Managed block content has drifted.'
        Diff = $diff
    }
}

function Get-FileCopyInspection {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    if (-not (Test-Path -LiteralPath $Resource.Source -PathType Leaf)) {
        return @{ State = 'Conflict'; Message = 'Canonical source is missing.' }
    }
    if (-not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) {
        return @{ State = 'Missing'; Message = 'Copied file is missing.' }
    }
    $sourceHash = Get-ContentHash $Resource.Source
    $targetHash = Get-ContentHash $Resource.Path
    if ($sourceHash -eq $targetHash) {
        return @{ State = 'Compliant'; Message = 'Copied file matches source.' }
    }
    $diff = Get-TextDiff `
        -Old ([IO.File]::ReadAllText($Resource.Path)) `
        -New ([IO.File]::ReadAllText($Resource.Source)) `
        -Label ([IO.Path]::GetFileName($Resource.Path))
    if (
        $StateEntry -and
        $StateEntry.ContainsKey('content_hash') -and
        $targetHash -eq [string]$StateEntry.content_hash
    ) {
        return @{
            State = 'Drift'
            Message = 'Owned copied file is outdated.'
            Diff = $diff
        }
    }
    return @{
        State = 'Conflict'
        Message = 'Target content is not proven to be owned.'
        Diff = $diff
    }
}

function Get-JunctionInspection {
    param([Parameter(Mandatory)][object]$Resource)

    $item = Get-Item -LiteralPath $Resource.Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return @{ State = 'Missing'; Message = 'Junction is missing.' }
    }
    $expected = [IO.Path]::GetFullPath($Resource.Target).TrimEnd('\')
    $matches = @(
        @($item.Target) | Where-Object {
            $_ -and [string]::Equals(
                [IO.Path]::GetFullPath([string]$_).TrimEnd('\'),
                $expected,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    if ($item.LinkType -eq 'Junction' -and $matches.Count -gt 0) {
        return @{ State = 'Compliant'; Message = 'Junction target matches.' }
    }
    return @{ State = 'Conflict'; Message = 'Path is not the owned junction.' }
}

function Get-EnvironmentInspection {
    param([Parameter(Mandatory)][object]$Resource)

    $current = [Environment]::GetEnvironmentVariable(
        $Resource.Name,
        $Resource.Scope
    )
    if ([string]::IsNullOrEmpty($current)) {
        return @{ State = 'Missing'; Message = 'Environment value is missing.' }
    }
    if ([string]::Equals(
        $current,
        $Resource.Value,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        return @{ State = 'Compliant'; Message = 'Environment value matches.' }
    }
    return @{
        State = 'Conflict'
        Message = 'Environment value is not owned by this wiring.'
    }
}

function Get-ResourceInspection {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    switch ($Resource.ResourceType) {
        'ManagedBlock' {
            return Get-ManagedBlockInspection $Resource $StateEntry
        }
        'FileCopy' {
            return Get-FileCopyInspection $Resource $StateEntry
        }
        'Junction' {
            return Get-JunctionInspection $Resource
        }
        'Environment' {
            return Get-EnvironmentInspection $Resource
        }
        default {
            throw "Unsupported GovernanceWiring resource: $($Resource.ResourceType)"
        }
    }
}

function Get-GovernanceWiringPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Resources,
        [ValidateSet('Apply', 'Remove', 'Check')]
        [string]$Action,
        [Parameter(Mandatory)][string]$StatePath
    )

    $state = Read-WiringState $StatePath
    $keys = @($Resources | ForEach-Object { Get-ResourceKey $_ })
    $duplicates = @(
        $keys | Group-Object | Where-Object Count -GT 1
    )
    if ($duplicates.Count -gt 0) {
        throw (
            'GovernanceWiring desired state contains duplicate resource keys: ' +
            (($duplicates | Select-Object -ExpandProperty Name) -join ', ')
        )
    }
    foreach ($resource in $Resources) {
        $key = Get-ResourceKey $resource
        $stateEntry = if ($state.resources.ContainsKey($key)) {
            $state.resources[$key]
        } else {
            $null
        }
        $inspection = Get-ResourceInspection $resource $stateEntry
        $desiredState = if (
            $resource.PSObject.Properties.Name -contains 'DesiredState'
        ) { [string]$resource.DesiredState } else { 'Present' }
        $effectiveAction = if (
            $Action -eq 'Apply' -and $desiredState -ceq 'Absent'
        ) { 'Remove' } else { $Action }
        $expectedState = if (
            $Action -eq 'Remove' -or $desiredState -ceq 'Absent'
        ) { 'Missing' } else { 'Compliant' }
        $operation = switch ($effectiveAction) {
            'Check' { 'None' }
            'Apply' {
                switch ($inspection.State) {
                    'Missing' { 'Create' }
                    'Drift' { 'Update' }
                    'Compliant' { 'None' }
                    default { 'Conflict' }
                }
            }
            'Remove' {
                switch ($inspection.State) {
                    'Missing' { 'None' }
                    'Compliant' { 'Remove' }
                    'Drift' { 'Remove' }
                    default { 'Conflict' }
                }
            }
        }
        $message = $inspection.Message
        if (
            $Action -eq 'Apply' -and
            $desiredState -ceq 'Absent' -and
            $inspection.State -ne 'Missing' -and
            $null -eq $stateEntry
        ) {
            $operation = 'Conflict'
            $message = (
                'Absent desired state cannot remove a path without ' +
                'GovernanceWiring ownership state.'
            )
        }
        [pscustomobject]@{
            Resource = $resource
            Key = $key
            State = $inspection.State
            Operation = $operation
            EffectiveAction = $effectiveAction
            ExpectedState = $expectedState
            Message = $message
            Diff = if ($inspection.ContainsKey('Diff')) { $inspection.Diff } else { $null }
        }
    }
}
