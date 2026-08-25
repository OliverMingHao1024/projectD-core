Set-StrictMode -Version Latest

function Get-SensitiveValuePatterns {
    return @(
        '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
        '\bgh[pousr]_[A-Za-z0-9]{20,}\b',
        '\bgithub_pat_[A-Za-z0-9_]{20,}\b',
        '\bsk-[A-Za-z0-9_-]{20,}\b',
        '\bAKIA[0-9A-Z]{16}\b',
        '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}'
    )
}

function Test-ContainsSensitiveValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    foreach ($pattern in Get-SensitiveValuePatterns) {
        if ($Text -match $pattern) { return $true }
    }
    return $false
}

function Find-SensitiveValue {
    param($Value, [string]$Path = '$')
    if ($null -eq $Value) { return @() }
    $hits = @()
    if ($Value -is [string]) {
        if (Test-ContainsSensitiveValue -Text $Value) { $hits += $Path }
    } elseif (
        $Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]
    ) {
        foreach ($property in $Value.PSObject.Properties) {
            $hits += @(Find-SensitiveValue $property.Value "$Path.$($property.Name)")
        }
    } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
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

function Resolve-RepositoryPath {
    <#
    $Path is supplied directly by a trusted caller (e.g. a CLI parameter).
    Still enforced to resolve inside $Root, exist, avoid reparse points, and
    respect a size limit. Use Resolve-RepositoryReference instead when the
    path string itself comes from untrusted data (evidence/plan JSON).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][long]$MaximumBytes
    )
    $resolved = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $Root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must stay inside the repository."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Label does not exist."
    }
    if (Test-PathHasReparsePoint -Root $Root -ResolvedPath $resolved) {
        throw "$Label must not cross a reparse point."
    }
    if ((Get-Item -LiteralPath $resolved -Force).Length -gt $MaximumBytes) {
        throw "$Label exceeds the $MaximumBytes byte input limit."
    }
    return $resolved
}

function Resolve-RepositoryReference {
    <#
    $Reference is an untrusted repository-relative string (e.g. a path
    named inside evidence/plan JSON supplied by an eval subject). Rejected
    up front if rooted or containing '..' before it is ever joined to
    $Root. Pass -Errors to accumulate failures instead of throwing on the
    first one; omit it to throw immediately.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][long]$MaximumBytes,
        [Collections.Generic.List[string]]$Errors
    )
    function Fail([string]$Message) {
        if ($null -ne $Errors) {
            $Errors.Add($Message)
            return $null
        }
        throw $Message
    }
    if (
        [string]::IsNullOrWhiteSpace($Reference) -or
        [IO.Path]::IsPathRooted($Reference) -or
        $Reference -split '[\\/]' -contains '..'
    ) {
        return Fail "$Label must be a repository-relative path without traversal."
    }
    $resolved = [IO.Path]::GetFullPath((
        Join-Path $Root ($Reference -replace '/', [IO.Path]::DirectorySeparatorChar)
    ))
    $rootPrefix = $Root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return Fail "$Label resolves outside the repository."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        return Fail "$Label does not exist."
    }
    if (Test-PathHasReparsePoint -Root $Root -ResolvedPath $resolved) {
        return Fail "$Label crosses a reparse point."
    }
    if ((Get-Item -LiteralPath $resolved -Force).Length -gt $MaximumBytes) {
        return Fail "$Label exceeds the $MaximumBytes byte input limit."
    }
    return $resolved
}

function Get-RepositoryReference {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )
    return [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return 'sha256:' + [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))
    ).ToLowerInvariant()
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(
        ($Text -replace "\r\n?", "`n")
    )
    return 'sha256:' + [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function Get-CanonicalTextSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $text = $utf8.GetString([IO.File]::ReadAllBytes($Path))
    return Get-TextSha256 -Text $text
}

Export-ModuleMember -Function @(
    'Get-SensitiveValuePatterns',
    'Test-ContainsSensitiveValue',
    'Find-SensitiveValue',
    'Test-PathHasReparsePoint',
    'Resolve-RepositoryPath',
    'Resolve-RepositoryReference',
    'Get-RepositoryReference',
    'Get-FileSha256',
    'Get-TextSha256',
    'Get-CanonicalTextSha256'
)
