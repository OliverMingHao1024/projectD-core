[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$FleetPath,[switch]$Json,[switch]$SkipGlobal,[switch]$SkipWiring)
$ErrorActionPreference='Stop';$core=[IO.Path]::GetFullPath($ProjectRoot);if([string]::IsNullOrWhiteSpace($FleetPath)){$FleetPath=Join-Path $core 'fleet\fleet.json'};$results=@()
function Add-Result([string]$n,[bool]$p,[string]$m){$script:results+=,[pscustomobject]@{name=$n;passed=$p;message=$m}}
$packsRoot=Join-Path $core 'packs';$packs=@(Get-ChildItem $packsRoot -Directory|Where-Object Name -NotLike '_*');$bad=@();foreach($pack in $packs){$skill=Join-Path $pack.FullName 'SKILL.md';if(-not(Test-Path $skill)){$bad+="$($pack.Name): missing SKILL.md";continue};$lines=Get-Content $skill -TotalCount 8;$name=@($lines|Where-Object{$_ -match '^name:\s*(\S+)'});if($name.Count -ne 1 -or $name[0] -notmatch "^name:\s*$([regex]::Escape($pack.Name))\s*$"){$bad+="$($pack.Name): name mismatch"}};if($bad.Count){Add-Result 'pack-catalog' $false ($bad -join '; ')}else{Add-Result 'pack-catalog' $true "$($packs.Count) pack(s) valid"}
if(-not(Test-Path $FleetPath)){Add-Result 'fleet-catalog' $false "Fleet file not found: $FleetPath"}else{try{$items=@(Get-Content -Raw $FleetPath|ConvertFrom-Json|ForEach-Object{$_});$bad=@();foreach($item in $items){if(-not(Test-Path $item.path)){$bad+="project path missing: $($item.path)"};foreach($pack in @($item.packs)){if(-not(Test-Path (Join-Path $core "packs\$pack\SKILL.md"))){$bad+="$($item.path): missing pack $pack"}}};if($bad.Count){Add-Result 'fleet-catalog' $false ($bad -join '; ')}else{Add-Result 'fleet-catalog' $true "$($items.Count) project(s) valid"}}catch{Add-Result 'fleet-catalog' $false "Invalid JSON: $($_.Exception.Message)"}}
$files=@(Get-ChildItem $core -Recurse -File|Where-Object{$_.FullName -notmatch '\\.git\\|\\.local\\|\\node_modules\\|\\packs\\_staging\\' -and $_.Name -ne 'projectd-check.ps1'});$hits=@($files|Select-String @('frontend-react-angular','typescript-node') -SimpleMatch -ErrorAction SilentlyContinue);if($hits.Count){Add-Result 'stale-pack-references' $false (($hits|Select-Object -First 10|%{"$($_.Path):$($_.LineNumber)"}) -join '; ')}else{Add-Result 'stale-pack-references' $true 'No retired pack references found'}
function Child([string]$n,[scriptblock]$a){
    try {
        $global:LASTEXITCODE = 0
        &$a | Out-Null
        if ($global:LASTEXITCODE -ne 0) {
            throw "Child check exited with code $global:LASTEXITCODE."
        }
        Add-Result $n $true 'Child check passed'
    } catch {
        Add-Result $n $false $_.Exception.Message
    }
}
if(-not$SkipWiring){$pwsh=Get-Command pwsh -ErrorAction SilentlyContinue;if($null -eq $pwsh){if(-not$SkipGlobal){Add-Result 'global-wiring' $false 'pwsh executable not found; install PowerShell 7 to run wiring checks'};Add-Result 'fleet-wiring' $false 'pwsh executable not found; install PowerShell 7 to run wiring checks'}else{if(-not$SkipGlobal){Child 'global-wiring'{& $pwsh.Source -NoProfile -File (Join-Path $PSScriptRoot 'setup.ps1') -Mode Check}};Child 'fleet-wiring'{& $pwsh.Source -NoProfile -File (Join-Path $PSScriptRoot 'fleet-governance.ps1') -Mode Check -FleetPath $FleetPath}}}else{Add-Result 'wiring' $true 'Skipped for isolated fixture checks'}
$failed=@($results|?{-not$_.passed});if($Json){[pscustomobject]@{passed=(!$failed.Count);checks=$results}|ConvertTo-Json -Depth 4}else{$results|%{"[$(if($_.passed){'PASS'}else{'FAIL'})] $($_.name): $($_.message)"};"Summary: $(@($results|? passed).Count) passed, $($failed.Count) failed."};if($failed.Count){exit 1}
