# Part of ProjectD.GovernanceWiring.psm1; dot-sourced into that module.
# Snapshots, writes, rollback, and the Invoke-GovernanceWiring entry point.

function Get-ResourceSnapshot {
    param([Parameter(Mandatory)][object]$Resource)

    switch ($Resource.ResourceType) {
        { $_ -in @('ManagedBlock', 'FileCopy') } {
            $exists = Test-Path -LiteralPath $Resource.Path -PathType Leaf
            return @{
                ResourceType = $Resource.ResourceType
                Path = $Resource.Path
                Exists = $exists
                Bytes = if ($exists) {
                    [IO.File]::ReadAllBytes($Resource.Path)
                } else {
                    $null
                }
            }
        }
        'Junction' {
            $item = Get-Item -LiteralPath $Resource.Path -Force `
                -ErrorAction SilentlyContinue
            return @{
                ResourceType = 'Junction'
                Path = $Resource.Path
                Exists = $null -ne $item
                Target = if ($item) { @($item.Target)[0] } else { $null }
                LinkType = if ($item) { $item.LinkType } else { $null }
            }
        }
        'Environment' {
            return @{
                ResourceType = 'Environment'
                Name = $Resource.Name
                Scope = $Resource.Scope
                Value = [Environment]::GetEnvironmentVariable(
                    $Resource.Name,
                    $Resource.Scope
                )
            }
        }
    }
}

function Restore-ResourceSnapshot {
    param([Parameter(Mandatory)][hashtable]$Snapshot)

    switch ($Snapshot.ResourceType) {
        { $_ -in @('ManagedBlock', 'FileCopy') } {
            if ($Snapshot.Exists) {
                New-Item -ItemType Directory -Path (
                    Split-Path $Snapshot.Path -Parent
                ) -Force | Out-Null
                [IO.File]::WriteAllBytes($Snapshot.Path, $Snapshot.Bytes)
            } else {
                Remove-Item -LiteralPath $Snapshot.Path -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        'Junction' {
            Remove-Item -LiteralPath $Snapshot.Path -Force `
                -ErrorAction SilentlyContinue
            if ($Snapshot.Exists -and $Snapshot.LinkType -eq 'Junction') {
                New-Item -ItemType Directory -Path (
                    Split-Path $Snapshot.Path -Parent
                ) -Force | Out-Null
                New-Item -ItemType Junction -Path $Snapshot.Path `
                    -Target $Snapshot.Target | Out-Null
            }
        }
        'Environment' {
            [Environment]::SetEnvironmentVariable(
                $Snapshot.Name,
                $Snapshot.Value,
                $Snapshot.Scope
            )
        }
    }
}

function Set-ManagedBlockContent {
    param([Parameter(Mandatory)][object]$Resource)

    $parent = Split-Path $Resource.Path -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $content = if (Test-Path -LiteralPath $Resource.Path -PathType Leaf) {
        [IO.File]::ReadAllText($Resource.Path)
    } else {
        ''
    }
    $newLine = Get-NewLine $content
    $block = (Normalize-WiringText $Resource.Content) -replace "`n", $newLine
    $pattern = [regex]::new(
        [regex]::Escape($Resource.BlockStart) +
            '.*?' +
            [regex]::Escape($Resource.BlockEnd),
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($pattern.IsMatch($content)) {
        $updated = $pattern.Replace($content, $block, 1)
    } else {
        $prefix = $content.TrimEnd([char[]]"`r`n")
        $updated = if ([string]::IsNullOrEmpty($prefix)) {
            $block + $newLine
        } else {
            $prefix + $newLine + $newLine + $block + $newLine
        }
    }
    [IO.File]::WriteAllText(
        $Resource.Path,
        $updated,
        [Text.UTF8Encoding]::new($false)
    )
}

function Remove-ManagedBlockContent {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [hashtable]$StateEntry
    )

    if (-not (Test-Path -LiteralPath $Resource.Path -PathType Leaf)) {
        return
    }
    $content = [IO.File]::ReadAllText($Resource.Path)
    $newLine = Get-NewLine $content
    $pattern = [regex]::new(
        [regex]::Escape($Resource.BlockStart) +
            '.*?' +
            [regex]::Escape($Resource.BlockEnd),
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    $updated = $pattern.Replace($content, '', 1).TrimEnd()
    if (
        [string]::IsNullOrWhiteSpace($updated) -and
        $StateEntry -and
        $StateEntry.created
    ) {
        Remove-Item -LiteralPath $Resource.Path -Force
        return
    }
    $final = if ($updated) { $updated + $newLine } else { '' }
    [IO.File]::WriteAllText(
        $Resource.Path,
        $final,
        [Text.UTF8Encoding]::new($false)
    )
}

function Invoke-ResourceMutation {
    param(
        [Parameter(Mandatory)][object]$PlanItem,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][hashtable]$State
    )

    $resource = $PlanItem.Resource
    $stateEntry = if ($State.resources.ContainsKey($PlanItem.Key)) {
        $State.resources[$PlanItem.Key]
    } else {
        $null
    }
    if ($PlanItem.Operation -eq 'None') {
        if ($Action -eq 'Remove') {
            $State.resources.Remove($PlanItem.Key)
            return
        }
        if (
            $Action -eq 'Apply' -and
            $resource.ResourceType -eq 'FileCopy' -and
            -not $stateEntry
        ) {
            $State.resources[$PlanItem.Key] = @{
                resource_type = 'FileCopy'
                content_hash = Get-ContentHash $resource.Path
            }
        }
        return
    }
    if ($Action -eq 'Apply') {
        switch ($resource.ResourceType) {
            'ManagedBlock' {
                $targetExisted = Test-Path `
                    -LiteralPath $resource.Path `
                    -PathType Leaf
                Set-ManagedBlockContent $resource
                $created = if (-not $targetExisted) {
                    $true
                } elseif ($stateEntry) {
                    [bool]$stateEntry.created
                } else {
                    $false
                }
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'ManagedBlock'
                    created = $created
                }
            }
            'FileCopy' {
                New-Item -ItemType Directory -Path (
                    Split-Path $resource.Path -Parent
                ) -Force | Out-Null
                Copy-Item -LiteralPath $resource.Source `
                    -Destination $resource.Path -Force
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'FileCopy'
                    content_hash = Get-ContentHash $resource.Path
                }
            }
            'Junction' {
                New-Item -ItemType Directory -Path (
                    Split-Path $resource.Path -Parent
                ) -Force | Out-Null
                New-Item -ItemType Junction -Path $resource.Path `
                    -Target $resource.Target | Out-Null
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'Junction'
                    target = $resource.Target
                }
            }
            'Environment' {
                [Environment]::SetEnvironmentVariable(
                    $resource.Name,
                    $resource.Value,
                    $resource.Scope
                )
                $State.resources[$PlanItem.Key] = @{
                    resource_type = 'Environment'
                    value = $resource.Value
                }
            }
        }
        return
    }

    switch ($resource.ResourceType) {
        'ManagedBlock' {
            Remove-ManagedBlockContent $resource $stateEntry
        }
        'FileCopy' {
            Remove-Item -LiteralPath $resource.Path -Force
        }
        'Junction' {
            Remove-Item -LiteralPath $resource.Path -Force
        }
        'Environment' {
            [Environment]::SetEnvironmentVariable(
                $resource.Name,
                $null,
                $resource.Scope
            )
        }
    }
    $State.resources.Remove($PlanItem.Key)
}

function Invoke-GovernanceWiring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Resources,
        [ValidateSet('Apply', 'Remove', 'Check')]
        [string]$Action,
        [Parameter(Mandatory)][string]$StatePath,
        [scriptblock]$AfterMutation
    )

    $plan = @(
        Get-GovernanceWiringPlan `
            -Resources $Resources `
            -Action $Action `
            -StatePath $StatePath
    )
    if ($Action -eq 'Check') {
        return $plan
    }
    $conflicts = @($plan | Where-Object Operation -EQ 'Conflict')
    if ($conflicts.Count -gt 0) {
        $details = ($conflicts | ForEach-Object {
            "$($_.Resource.ResourceType): $($_.Message)"
        }) -join '; '
        throw "GovernanceWiring preflight conflict: $details"
    }

    $state = Read-WiringState $StatePath
    $stateSnapshot = @{
        Exists = Test-Path -LiteralPath $StatePath -PathType Leaf
        Bytes = if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
            [IO.File]::ReadAllBytes($StatePath)
        } else {
            $null
        }
    }
    $mutations = @($plan | Where-Object Operation -NE 'None')
    $snapshots = @(
        $mutations | ForEach-Object {
            Get-ResourceSnapshot $_.Resource
        }
    )
    try {
        foreach ($item in $plan) {
            Invoke-ResourceMutation `
                -PlanItem $item `
                -Action $item.EffectiveAction `
                -State $state
            if ($item.Operation -ne 'None' -and $AfterMutation) {
                & $AfterMutation $item
            }
        }
        Write-WiringState -StatePath $StatePath -State $state
        $verification = @(
            Get-GovernanceWiringPlan `
                -Resources $Resources `
                -Action Check `
                -StatePath $StatePath
        )
        $failed = @(
            if ($Action -eq 'Remove') {
                $verification | Where-Object State -NE 'Missing'
            } else {
                $verification |
                    Where-Object { $_.State -ne $_.ExpectedState }
            }
        )
        if ($failed.Count -gt 0) {
            $details = ($failed | ForEach-Object {
                "$($_.Resource.ResourceType)[$($_.Key)]: " +
                    "$($_.State) ($($_.Message))"
            }) -join '; '
            throw (
                "GovernanceWiring verification failed after ${Action}: " +
                $details
            )
        }
    } catch {
        for ($index = $snapshots.Count - 1; $index -ge 0; $index--) {
            Restore-ResourceSnapshot $snapshots[$index]
        }
        if ($stateSnapshot.Exists) {
            New-Item -ItemType Directory -Path (
                Split-Path $StatePath -Parent
            ) -Force | Out-Null
            [IO.File]::WriteAllBytes($StatePath, $stateSnapshot.Bytes)
        } else {
            Remove-Item -LiteralPath $StatePath -Force `
                -ErrorAction SilentlyContinue
        }
        throw
    }
    return $plan
}
