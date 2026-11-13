# Part of ProjectD.GovernanceWiring.psm1; dot-sourced into that module.
# Ownership state file, resource keys, hashing, and text helpers.

function Get-ResourceKey {
    param([Parameter(Mandatory)][object]$Resource)

    $identity = if ($Resource.ResourceType -eq 'Environment') {
        "$($Resource.Scope)|$($Resource.Name)"
    } else {
        [string]$Resource.Path
    }
    return (
        "$($Resource.ResourceType)|$identity"
    ).ToLowerInvariant()
}

function Read-WiringState {
    param([Parameter(Mandatory)][string]$StatePath)

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return @{
            schema_version = 1
            resources = @{}
        }
    }
    $state = Get-Content -Raw -LiteralPath $StatePath |
        ConvertFrom-Json -AsHashtable
    if ($state.schema_version -ne 1) {
        throw "Unsupported GovernanceWiring state schema: $($state.schema_version)"
    }
    if (-not $state.ContainsKey('resources')) {
        $state.resources = @{}
    }
    return $state
}

function Write-WiringState {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][hashtable]$State
    )

    $parent = Split-Path $StatePath -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ".$(Split-Path $StatePath -Leaf).$PID.tmp"
    try {
        $json = $State | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText(
            $temporary,
            $json + "`n",
            [Text.UTF8Encoding]::new($false)
        )
        Move-Item -LiteralPath $temporary -Destination $StatePath -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-ContentHash {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextDiff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Old,
        [Parameter(Mandatory)][AllowEmptyString()][string]$New,
        [string]$Label = 'content'
    )

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        return $null
    }
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) (
        "projectd-wiring-diff-$PID-$([Guid]::NewGuid().ToString('N'))"
    )
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $safeLabel = $Label -replace '[\\/:*?"<>|]', '_'
        $oldPath = Join-Path $tempDir "a-$safeLabel"
        $newPath = Join-Path $tempDir "b-$safeLabel"
        [IO.File]::WriteAllText($oldPath, $Old, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($newPath, $New, [Text.UTF8Encoding]::new($false))
        $diff = & git diff --no-index --no-color -- $oldPath $newPath 2>$null
        if (-not $diff) {
            return $null
        }
        return ($diff -join "`n")
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-WiringText {
    param([AllowEmptyString()][string]$Value)

    return (($Value -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Get-NewLine {
    param([AllowEmptyString()][string]$Content)

    if ($Content.Contains("`r`n")) {
        return "`r`n"
    }
    return "`n"
}
