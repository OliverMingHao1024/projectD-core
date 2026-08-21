[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$core = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$validator = Join-Path $core 'scripts\governance-asset-inventory.ps1'
$inventory = Join-Path $core 'evals\governance-assets.json'
$inventorySchema = Join-Path $core 'evals\schemas\governance-assets.schema.json'
$catalog = Join-Path $core 'evals\governance-behavior-cases.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "governance-assets-$PID"
$junctionPath = Join-Path $tempRoot 'linked-scripts'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Test-InvalidInventory {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Name
    )
    $path = Join-Path $tempRoot "$Name.json"
    $stdout = Join-Path $tempRoot "$Name.stdout.json"
    $Value | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $path -Encoding utf8
    $process = Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
        '-NoProfile', '-File', $validator,
        '-ProjectRoot', $tempRoot,
        '-InventoryPath', $path,
        '-InventorySchemaPath', $inventorySchema,
        '-BehaviorCatalogPath', $catalog,
        '-Json'
    ) -RedirectStandardOutput $stdout -Wait -PassThru -WindowStyle Hidden
    $result = Get-Content -Raw -LiteralPath $stdout | ConvertFrom-Json
    Assert-True ($process.ExitCode -ne 0) "$Name must return a non-zero exit code."
    Assert-True (-not $result.passed) "$Name JSON must report failure."
}

function New-Asset {
    [pscustomobject]@{
        id = 'fixture-tool'
        kind = 'tool'
        owner = 'fixture-owner'
        status = 'active'
        risk_tier = 'high'
        source = [pscustomobject]@{
            type = 'external'; reference = 'fixture'; version = '1.0'
            integrity = 'sha256:' + ('0' * 64)
        }
        capabilities = [pscustomobject]@{
            read = $true; write = $true; destructive = $false
            open_world = $true; private_data = $true
            untrusted_content = $true; external_communication = $true
        }
        controls = [pscustomobject]@{
            approval_policy = 'high-risk-actions'
            isolation = 'sandbox-and-egress-policy'
            source_sink_policy = 'block-private-untrusted-to-external'
            disable_procedure = 'Disable fixture tool registration.'
        }
        related_eval_cases = @('source-does-not-authorize-action')
    }
}

function New-Inventory([object]$Asset) {
    [pscustomobject]@{
        schema_version = 1
        scope = 'contract-fixture'
        owner = 'fixture-owner'
        coverage_exclusions = @()
        assets = @($Asset)
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $healthy = & $validator -ProjectRoot $core -InventoryPath $inventory `
        -BehaviorCatalogPath $catalog -Json | ConvertFrom-Json
    Assert-True $healthy.passed 'Canonical governance inventory must pass.'
    Assert-True ($healthy.evaluated -ge 8) 'Canonical inventory must cover core assets.'
    $canonical = Get-Content -Raw -LiteralPath $inventory | ConvertFrom-Json
    foreach ($kind in @('agent', 'model', 'skill_catalog', 'tool')) {
        Assert-True ($kind -cin @($canonical.assets.kind)) (
            "Canonical inventory must cover $kind assets."
        )
    }
    Assert-True (@($canonical.coverage_exclusions).Count -ge 1) (
        'Unknown host-runtime assets must be an explicit coverage exclusion.'
    )

    $lethal = New-Asset
    $lethal.controls.source_sink_policy = ''
    Test-InvalidInventory (New-Inventory $lethal) 'lethal-trifecta-without-policy'

    $noDisable = New-Asset
    $noDisable.controls.disable_procedure = ''
    Test-InvalidInventory (New-Inventory $noDisable) 'high-risk-without-disable'

    $credential = New-Asset
    $credential.id = 'embedded-credential'
    $credential.kind = 'credential'
    $credential | Add-Member -NotePropertyName token -NotePropertyValue 'do-not-store'
    Test-InvalidInventory (New-Inventory $credential) 'embedded-secret'

    $unknownEval = New-Asset
    $unknownEval.related_eval_cases = @('not-a-real-case')
    Test-InvalidInventory (New-Inventory $unknownEval) 'unknown-eval-case'

    $unsafePath = New-Asset
    $unsafePath.source.type = 'repository-local'
    $unsafePath.source.reference = '..\outside.ps1'
    Test-InvalidInventory (New-Inventory $unsafePath) 'unsafe-local-path'

    $fixtureScript = Join-Path $tempRoot 'fixture.ps1'
    Set-Content -LiteralPath $fixtureScript -Value '# fixture' -Encoding utf8
    $wrongIntegrity = New-Asset
    $wrongIntegrity.source.type = 'repository-local'
    $wrongIntegrity.source.reference = 'fixture.ps1'
    $wrongIntegrity.source.integrity = 'sha256:' + ('0' * 64)
    Test-InvalidInventory (New-Inventory $wrongIntegrity) 'integrity-mismatch'

    New-Item -ItemType Junction -Path $junctionPath `
        -Target (Join-Path $core 'scripts') | Out-Null
    $reparse = New-Asset
    $reparse.source.type = 'repository-local'
    $reparse.source.reference = 'linked-scripts/projectd-check.ps1'
    $reparse.source.integrity = 'sha256:' + (
        Get-FileHash -Algorithm SHA256 `
            -LiteralPath (Join-Path $core 'scripts\projectd-check.ps1')
    ).Hash.ToLowerInvariant()
    Test-InvalidInventory (New-Inventory $reparse) 'reparse-point-source'

    Write-Output 'GOVERNANCE_ASSET_INVENTORY_CONTRACT_OK'
} finally {
    if (Test-Path -LiteralPath $junctionPath) {
        $validatedTempRoot = [IO.Path]::GetFullPath($tempRoot)
        $validatedJunction = [IO.Path]::GetFullPath($junctionPath)
        if (-not $validatedJunction.StartsWith(
            $validatedTempRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw 'Refusing to remove a junction outside the contract temp root.'
        }
        $junction = Get-Item -LiteralPath $validatedJunction -Force
        if (-not ($junction.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Refusing cleanup because linked-scripts is not a reparse point.'
        }
        Remove-Item -LiteralPath $validatedJunction -Force
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
