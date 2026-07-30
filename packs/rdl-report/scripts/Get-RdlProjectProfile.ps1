[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$ProjectRoot,

    [switch]$IsSummaryOnly,

    [switch]$ShouldIncludeGeneratedArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AlwaysExcludedDirectories = @('.git', 'node_modules', 'packages')
$GeneratedArtifactDirectories = @('bin', 'obj', 'dist')
$EncodingProbeLength = 256
$Utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)
$JsonDepth = 10

function Get-ReportArtifacts([string]$root, [bool]$shouldIncludeGeneratedArtifacts) {
    $excluded = @($AlwaysExcludedDirectories)
    if (-not $shouldIncludeGeneratedArtifacts) { $excluded += $GeneratedArtifactDirectories }
    $pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pending.Push([System.IO.DirectoryInfo]::new($root))
    $files = @()
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        try {
            $files += @($directory.GetFiles() | Where-Object { $_.Extension -in '.rdl', '.rptproj', '.rds', '.rsd' })
            foreach ($child in $directory.GetDirectories()) {
                if ($child.Name -notin $excluded) { $pending.Push($child) }
            }
        } catch {
            Write-Warning ("Skipped unreadable directory '{0}': {1}" -f $directory.FullName, $_.Exception.Message)
        }
    }
    return @($files)
}

function Get-DeclaredEncoding([string]$path) {
    $reader = [System.IO.StreamReader]::new($path, $true)
    try {
        $buffer = New-Object char[] $EncodingProbeLength
        $count = $reader.Read($buffer, 0, $buffer.Length)
        if ($count -eq 0) { return $null }
        $head = -join $buffer[0..([Math]::Max(0, $count - 1))]
        $match = [regex]::Match($head, 'encoding\s*=\s*["''](?<value>[^"'']+)', 'IgnoreCase')
        if ($match.Success) { return $match.Groups['value'].Value }
        return $null
    } finally {
        $reader.Dispose()
    }
}

function Test-HasUtf8Bom([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        if ($stream.Length -lt $Utf8Bom.Length) { return $false }
        return ($stream.ReadByte() -eq $Utf8Bom[0] -and $stream.ReadByte() -eq $Utf8Bom[1] -and $stream.ReadByte() -eq $Utf8Bom[2])
    } finally {
        $stream.Dispose()
    }
}

function Read-XmlDocument([string]$path) {
    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $document.Load($path)
    return $document
}

function Get-NodeValues([System.Xml.XmlDocument]$document, [string]$xpath) {
    $values = foreach ($node in @($document.SelectNodes($xpath))) {
        if ($null -eq $node) { continue }
        $value = if ($node -is [System.Xml.XmlAttribute]) { $node.Value } else { $node.InnerText }
        if ($null -ne $value) { $value.Trim() }
    }
    return @($values | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-ChildText([System.Xml.XmlNode]$node, [string]$localName) {
    $child = $node.SelectSingleNode("./*[local-name()='$localName']")
    if ($child) { return $child.InnerText.Trim() }
    return $null
}

function Get-PageProfile([System.Xml.XmlDocument]$document) {
    $page = $document.SelectSingleNode('//*[local-name()="Page"]')
    $body = $document.SelectSingleNode('//*[local-name()="Body"]')
    $section = $document.SelectSingleNode('//*[local-name()="ReportSection"]')
    if (-not $page) { return $null }
    $bodyWidth = if ($body) { Get-ChildText $body 'Width' } else { $null }
    if (-not $bodyWidth -and $section) { $bodyWidth = Get-ChildText $section 'Width' }
    return [ordered]@{
        width = Get-ChildText $page 'PageWidth'
        height = Get-ChildText $page 'PageHeight'
        leftMargin = Get-ChildText $page 'LeftMargin'
        rightMargin = Get-ChildText $page 'RightMargin'
        topMargin = Get-ChildText $page 'TopMargin'
        bottomMargin = Get-ChildText $page 'BottomMargin'
        bodyWidth = $bodyWidth
    }
}

function Get-QueryParameterProfiles([System.Xml.XmlNode]$dataSet) {
    return @($dataSet.SelectNodes('.//*[local-name()="QueryParameter"]') | ForEach-Object {
        [ordered]@{
            name = if ($_.Attributes['Name']) { $_.Attributes['Name'].Value } else { $null }
            value = Get-ChildText $_ 'Value'
        }
    })
}

function Get-FieldProfiles([System.Xml.XmlNode]$dataSet) {
    return @($dataSet.SelectNodes('./*[local-name()="Fields"]/*[local-name()="Field"]') | ForEach-Object {
        [ordered]@{
            name = if ($_.Attributes['Name']) { $_.Attributes['Name'].Value } else { $null }
            dataField = Get-ChildText $_ 'DataField'
            typeName = Get-ChildText $_ 'TypeName'
        }
    })
}

function Get-DataSetProfiles([System.Xml.XmlDocument]$document) {
    return @($document.SelectNodes('//*[local-name()="DataSets"]/*[local-name()="DataSet"]') | ForEach-Object {
        $sharedReference = $_.SelectSingleNode('.//*[local-name()="SharedDataSetReference"]')
        $query = $_.SelectSingleNode('./*[local-name()="Query"]')
        [ordered]@{
            name = if ($_.Attributes['Name']) { $_.Attributes['Name'].Value } else { $null }
            kind = if ($sharedReference) { 'Shared' } else { 'Embedded' }
            sharedDataSetReference = if ($sharedReference) { $sharedReference.InnerText.Trim() } else { $null }
            dataSourceName = if ($query) { Get-ChildText $query 'DataSourceName' } else { $null }
            commandType = if ($query) { Get-ChildText $query 'CommandType' } else { $null }
            commandText = if ($query) { Get-ChildText $query 'CommandText' } else { $null }
            queryParameters = @(Get-QueryParameterProfiles $_)
            fields = @(Get-FieldProfiles $_)
        }
    })
}

function Get-StoredProcedures([System.Xml.XmlDocument]$document) {
    $procedures = foreach ($query in @($document.SelectNodes('//*[local-name()="Query"]'))) {
        $type = $query.SelectSingleNode('./*[local-name()="CommandType"]')
        $text = $query.SelectSingleNode('./*[local-name()="CommandText"]')
        if ($type -and $text -and $type.InnerText.Trim() -eq 'StoredProcedure') {
            $text.InnerText.Trim()
        }
    }
    return @($procedures | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-ReportProfile([System.IO.FileInfo]$file) {
    $document = Read-XmlDocument $file.FullName
    return [ordered]@{
        name = $file.Name
        path = $file.FullName
        schema = $document.DocumentElement.NamespaceURI
        declaredEncoding = Get-DeclaredEncoding $file.FullName
        hasUtf8Bom = Test-HasUtf8Bom $file.FullName
        dataSourceReferences = @(Get-NodeValues $document '//*[local-name()="DataSourceReference"]')
        sharedDataSetReferences = @(Get-NodeValues $document '//*[local-name()="SharedDataSetReference"]')
        dataSets = @(Get-NodeValues $document '//*[local-name()="DataSet"]/@Name')
        parameters = @(Get-NodeValues $document '//*[local-name()="ReportParameter"]/@Name')
        dataSetContracts = @(Get-DataSetProfiles $document)
        storedProcedures = @(Get-StoredProcedures $document)
        tablixCount = @($document.SelectNodes('//*[local-name()="Tablix"]')).Count
        subreportCount = @($document.SelectNodes('//*[local-name()="Subreport"]')).Count
        page = Get-PageProfile $document
    }
}

function Get-ProjectConfigurations([System.Xml.XmlDocument]$document) {
    $result = foreach ($versionNode in @($document.SelectNodes('//*[local-name()="TargetServerVersion"]'))) {
        $anchor = $versionNode.ParentNode
        $condition = if ($anchor.Attributes['Condition']) { $anchor.Attributes['Condition'].Value } else { $null }
        $name = Get-ChildText $anchor 'Name'
        if (-not $name -and $anchor.ParentNode) { $name = Get-ChildText $anchor.ParentNode 'Name' }
        [ordered]@{
            name = $name
            condition = $condition
            targetServerVersion = $versionNode.InnerText.Trim()
            targetServerUrl = Get-ChildText $anchor 'TargetServerURL'
            targetFolder = Get-ChildText $anchor 'TargetFolder'
        }
    }
    return @($result)
}

function Get-IncludedReports([System.Xml.XmlDocument]$document) {
    $reports = @($document.SelectNodes('//*[local-name()="Report"]') | ForEach-Object {
        if ($_.Attributes['Include']) { $_.Attributes['Include'].Value } elseif ($_.InnerText) { $_.InnerText.Trim() }
    })
    $legacy = @($document.SelectNodes('//*[local-name()="Reports"]//*[local-name()="Name"]') |
        ForEach-Object { $_.InnerText.Trim() })
    return @(($reports + $legacy) | Where-Object { $_ -match '\.rdl$' } | Sort-Object -Unique)
}

function Get-ProjectFileProfile([System.IO.FileInfo]$file, [string[]]$physicalReports) {
    $document = Read-XmlDocument $file.FullName
    $included = @(Get-IncludedReports $document)
    $includedNames = @($included | ForEach-Object { Split-Path $_ -Leaf })
    return [ordered]@{
        name = $file.Name
        path = $file.FullName
        declaredEncoding = Get-DeclaredEncoding $file.FullName
        hasUtf8Bom = Test-HasUtf8Bom $file.FullName
        configurations = @(Get-ProjectConfigurations $document)
        includedReports = $included
        unlistedPhysicalReports = @($physicalReports | Where-Object { $_ -notin $includedNames })
    }
}

function ConvertTo-Counts([object[]]$values, [string]$propertyName) {
    $items = foreach ($group in @($values | Where-Object { $null -ne $_ -and "$_" })) {
        $group
    }
    return @($items | Group-Object | Sort-Object -Property Count, Name -Descending | ForEach-Object {
        [ordered]@{ $propertyName = $_.Name; count = $_.Count }
    })
}

function Get-DirectoryProfile([System.IO.DirectoryInfo]$directory, [bool]$isSummaryOnly) {
    $files = @(Get-ChildItem -LiteralPath $directory.FullName -File | Where-Object {
        $_.Extension -in '.rdl', '.rptproj', '.rds', '.rsd'
    })
    $rdlFiles = @($files | Where-Object Extension -eq '.rdl')
    $reportErrors = @()
    $reports = @(foreach ($file in $rdlFiles) {
        try { Get-ReportProfile $file } catch {
            $reportErrors += [ordered]@{ name = $file.Name; path = $file.FullName; error = $_.Exception.Message }
        }
    })
    $physicalNames = @($rdlFiles | ForEach-Object Name)
    $projects = @($files | Where-Object Extension -eq '.rptproj' |
        ForEach-Object { Get-ProjectFileProfile $_ $physicalNames })
    [object[]]$reportDetails = if ($isSummaryOnly) { @() } else { $reports }
    $profile = [ordered]@{
        path = $directory.FullName
        counts = [ordered]@{ rdl = $rdlFiles.Count; parsedRdl = $reports.Count; rptproj = $projects.Count; rds = @($files | Where-Object Extension -eq '.rds').Count; rsd = @($files | Where-Object Extension -eq '.rsd').Count }
        schemas = @(ConvertTo-Counts @($reports | ForEach-Object schema) 'value')
        dataSourceReferences = @(ConvertTo-Counts @($reports | ForEach-Object dataSourceReferences) 'value')
        sharedDataSetReferences = @(ConvertTo-Counts @($reports | ForEach-Object sharedDataSetReferences) 'value')
        parameters = @(ConvertTo-Counts @($reports | ForEach-Object parameters) 'value')
        projectFiles = $projects
        invalidReports = $reportErrors
        reports = $reportDetails
    }
    return $profile
}

$resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$artifacts = @(Get-ReportArtifacts $resolvedRoot $ShouldIncludeGeneratedArtifacts.IsPresent)
$directories = @($artifacts | ForEach-Object Directory | Sort-Object FullName -Unique)
$warnings = @()
if ($artifacts.Count -eq 0) { $warnings += 'No RDL report artifacts were found.' }

$result = [ordered]@{
    projectRoot = $resolvedRoot
    generatedAt = [DateTime]::UtcNow.ToString('o')
    artifactCount = $artifacts.Count
    reportDirectories = @($directories | ForEach-Object { Get-DirectoryProfile $_ $IsSummaryOnly.IsPresent })
    warnings = $warnings
}

$result | ConvertTo-Json -Depth $JsonDepth
