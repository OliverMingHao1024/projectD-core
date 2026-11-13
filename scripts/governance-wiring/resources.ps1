# Part of ProjectD.GovernanceWiring.psm1; dot-sourced into that module.
# Resource constructors (the unit of desired state).

function New-ManagedBlockResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BlockStart,
        [Parameter(Mandatory)][string]$BlockEnd,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Owner
    )

    if (
        -not $Content.Contains($BlockStart) -or
        -not $Content.Contains($BlockEnd)
    ) {
        throw 'Managed block content must contain both ownership markers.'
    }
    [pscustomobject]@{
        ResourceType = 'ManagedBlock'
        Path = [IO.Path]::GetFullPath($Path)
        BlockStart = $BlockStart
        BlockEnd = $BlockEnd
        Content = $Content.Trim()
        Owner = $Owner
    }
}

function New-FileCopyResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Owner
    )

    [pscustomobject]@{
        ResourceType = 'FileCopy'
        Path = [IO.Path]::GetFullPath($Path)
        Source = [IO.Path]::GetFullPath($Source)
        Owner = $Owner
    }
}

function New-JunctionResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Owner,
        [ValidateSet('Present', 'Absent')]
        [string]$DesiredState = 'Present'
    )

    [pscustomobject]@{
        ResourceType = 'Junction'
        Path = [IO.Path]::GetFullPath($Path)
        Target = [IO.Path]::GetFullPath($Target)
        Owner = $Owner
        DesiredState = $DesiredState
    }
}

function New-EnvironmentResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope = 'User',
        [Parameter(Mandatory)][string]$Owner
    )

    [pscustomobject]@{
        ResourceType = 'Environment'
        Name = $Name
        Value = $Value
        Scope = $Scope
        Owner = $Owner
    }
}
