<#
.SYNOPSIS
  Discover IIS dependencies (endpoints + config files + connection strings)
  based on inventory CSV.

.INPUT
  C:\IISDiscovery\Reports\IIS_Sites_Apps_VDirs.csv

.OUTPUT
  C:\IISDiscovery\Reports\IIS_Discovery_AllSites_CLEAN.csv
#>

[CmdletBinding()]
param(
  [string]$InputCsv  = "C:\IISDiscovery\Reports\IIS_Sites_Apps_VDirs.csv",
  [string]$OutputCsv = "C:\IISDiscovery\Reports\IIS_Discovery_AllSites_CLEAN.csv"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "Starting IIS dependency discovery..."
if (-not (Test-Path -LiteralPath $InputCsv)) {
    throw "Input CSV not found: $InputCsv"
}

$inventory = Import-Csv -LiteralPath $InputCsv
if (-not $inventory -or $inventory.Count -eq 0) {
    throw "Inventory CSV is empty."
}

Write-Host "Inventory loaded successfully. Rows:" $inventory.Count
# Build endpoint-only dependency rows (checkpoint)
$rows = New-Object System.Collections.Generic.List[object]

foreach ($r in $inventory) {

    # Determine IISPath + PhysicalPath based on vdir/app/root
    $iisPath = "/"
    if ($r.VDir_Path -and $r.VDir_Path.Trim() -ne "") { $iisPath = $r.VDir_Path }
    elseif ($r.App_Path -and $r.App_Path.Trim() -ne "") { $iisPath = $r.App_Path }

    $physPath = ""
    if ($r.VDir_Physical_Path -and $r.VDir_Physical_Path.Trim() -ne "") { $physPath = $r.VDir_Physical_Path }
    elseif ($r.App_Physical_Path -and $r.App_Physical_Path.Trim() -ne "") { $physPath = $r.App_Physical_Path }

    if ($r.Endpoint_Url -and $r.Endpoint_Url.Trim() -ne "") {
        $rows.Add([pscustomobject]@{
            SiteName         = $r.Site_Name
            IISPath          = $iisPath
            ItemType         = $r.Item_Type
            PhysicalPath     = $physPath
            BindingProtocol  = $r.Binding_Protocol
            BindingHost      = $r.Binding_Host
            BindingPort      = $r.Binding_Port
            EndpointUrl      = $r.Endpoint_Url
            ConfigPath       = ""
            ConnectionString = ""
        }) | Out-Null
    }
}

# Write CSV
$rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Dependency CSV created:" $OutputCsv
Write-Host "Rows written:" $rows.Count


# Directories and filenames to skip during config scan
$ExcludeDirs = @(
  'logs','log','node_modules','bin','obj','packages','.git','.svn','.vs',
  'dist','build','cache','temp','tmp','backup','backups','_old','old',
  'archive','archived','attic','.history','.idea','deploy','release'
)

$ExcludeFileSubstrings = @(
  'copy','_old','-old','.old','.bak','.backup','archive','archived','attic','.tmp','.temp'
)

# -------------------------
# BLOCK 4: Config scan + connection strings
# -------------------------

function Mask-Password([string]$s){
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    return [regex]::Replace($s,'(?i)(password|pwd)\s*=\s*[^;|]+','$1=******')
}

function Test-ExcludedDir([string]$FullPath,[string[]]$Names){
    if (-not $FullPath) { return $false }
    $p = '\'+($FullPath.ToLower().TrimEnd('\'))+'\'
    foreach($n in $Names){
        $needle = '\'+$n+'\'
        if ($p.Contains($needle)) { return $true }
    }
    return $false
}

function Should-SkipFile([string]$FullPath,[string[]]$substrings){
    $name = [System.IO.Path]::GetFileName($FullPath).ToLower()
    foreach($tok in $substrings){
        if ($name -like "*$tok*") { return $true }
    }
    return $false
}

function Get-ChildFilesFast([string]$Root,[string[]]$Patterns,[string[]]$ExcludeDirs,[string[]]$ExcludeFileSubstrings,[int]$MaxSizeBytes){
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $out }

    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)

    while($stack.Count -gt 0){
        $dir = [string]$stack.Pop()
        if (Test-ExcludedDir $dir $ExcludeDirs) { continue }

        try { $subs = Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue } catch { $subs = @() }
        foreach($s in $subs){ $stack.Push($s.FullName) }

        foreach($pat in $Patterns){
            try { $files = Get-ChildItem -LiteralPath $dir -Filter $pat -File -Force -ErrorAction SilentlyContinue } catch { $files = @() }
            foreach($f in $files){
                if ($f.Length -le $MaxSizeBytes -and -not (Should-SkipFile $f.FullName $ExcludeFileSubstrings)){
                    [void]$out.Add($f.FullName)
                }
            }
        }
    }
    return $out
}

function Get-ConnStringsFromXml([string]$XmlPath){
    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $XmlPath)) { return $items }

    try { $doc = [xml](Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8) }
    catch {
        $items.Add([pscustomobject]@{ConfigPath=$XmlPath; ConnectionString='[UNREADABLE or ENCRYPTED]'}) | Out-Null
        return $items
    }

    $nodes=@()
    $n1=$doc.SelectSingleNode('/configuration/connectionStrings'); if($n1){$nodes+=$n1}
    $n2=$doc.SelectSingleNode('/connectionStrings');               if($n2){$nodes+=$n2}

    foreach($cs in ($nodes | Select-Object -Unique)){
        # support configSource
        $attr=$cs.Attributes['configSource']
        if($attr -and $attr.Value){
            $base = Split-Path -Parent $XmlPath
            $ext  = if([IO.Path]::IsPathRooted($attr.Value)){ $attr.Value } else { Join-Path $base $attr.Value }
            if($ext -and (Test-Path -LiteralPath $ext)){
                try { $doc2=[xml](Get-Content -LiteralPath $ext -Raw -Encoding UTF8); $cs=$doc2.SelectSingleNode('/connectionStrings') } catch {}
            }
        }

        if($cs){
            foreach($add in $cs.SelectNodes('add')){
                $conn=$add.Attributes['connectionString'].Value
                if ($conn) { $items.Add([pscustomobject]@{ConfigPath=$XmlPath; ConnectionString=$conn}) | Out-Null }
            }
        }
    }
    return $items
}

function Get-ConnStringsFromJson([string]$JsonPath){
    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $JsonPath)) { return $items }
    try {
        $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $items }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch { return $items }

    if ($obj -and $obj.PSObject -and $obj.PSObject.Properties -and $obj.PSObject.Properties['ConnectionStrings']) {

        $cs = $obj.ConnectionStrings
        if ($cs -and $cs.PSObject -and $cs.PSObject.Properties) {
            foreach ($p in $cs.PSObject.Properties) {
                $val = [string]$p.Value
                if ($val) { $items.Add([pscustomobject]@{ConfigPath=$JsonPath; ConnectionString=$val}) | Out-Null }
            }
        }
    }
    return $items
}

# Build a per-site list of physical paths (longest match first), to map files back to IISPath
$physMap = @{}
foreach ($r in $inventory) {
    $site = [string]$r.Site_Name
    if (-not $physMap.ContainsKey($site)) {
        $physMap[$site] = New-Object System.Collections.Generic.List[object]
    }

    if ($r.App_Physical_Path -and $r.App_Physical_Path.Trim() -ne "") {
        $physMap[$site].Add(@{
            phys = [string]$r.App_Physical_Path
            iis  = if ($r.App_Path) { [string]$r.App_Path } else { "/" }
            type = if ($r.Item_Type) { [string]$r.Item_Type } else { "root" }
        }) | Out-Null
    }

    if ($r.VDir_Physical_Path -and $r.VDir_Physical_Path.Trim() -ne "") {
        $physMap[$site].Add(@{
            phys = [string]$r.VDir_Physical_Path
            iis  = if ($r.VDir_Path) { [string]$r.VDir_Path } else { "/" }
            type = "vdir"
        }) | Out-Null
    }
}

foreach ($k in @($physMap.Keys)) {
    $physMap[$k] = $physMap[$k] | Sort-Object { $_.phys.Length } -Descending
}

function Map-ToClosestIIS([string]$site,[string]$filePath){
    if (-not $site -or -not $filePath -or -not $physMap.ContainsKey($site)) {
        return @{ iis="/"; type="root" }
    }
    $p = $filePath.TrimEnd('\')
    foreach($m in $physMap[$site]){
        $mp = ([string]$m.phys).TrimEnd('\')
        if ($p.StartsWith($mp, $true, [Globalization.CultureInfo]::InvariantCulture)) {
            return @{ iis=$m.iis; type=$m.type }
        }
    }
    return @{ iis="/"; type="root" }
}

# Scan unique roots (site + physical path)
$scanRoots = New-Object 'System.Collections.Generic.Dictionary[string,hashtable]'
foreach ($r in $inventory) {
    $site = [string]$r.Site_Name

    $phys = ""
    if ($r.VDir_Physical_Path -and $r.VDir_Physical_Path.Trim() -ne "") { $phys = [string]$r.VDir_Physical_Path }
    elseif ($r.App_Physical_Path -and $r.App_Physical_Path.Trim() -ne "") { $phys = [string]$r.App_Physical_Path }

    if (-not $phys) { continue }

    $k = $site + "¦" + $phys
    if (-not $scanRoots.ContainsKey($k)) {
        $scanRoots[$k] = @{
            site = $site
            phys = $phys
        }
    }
}

$patterns = @('web.config','*.config','*.settings','appsettings*.json','*config*.json')
$maxBytes = 5MB  # keep safe; can raise later

# DEDUP map for config rows
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($r in $rows) {
    $k = "$($r.SiteName)|$($r.IISPath)|$($r.ItemType)|$($r.EndpointUrl)|$($r.ConfigPath)|$($r.ConnectionString)"
    [void]$seen.Add($k)
}

Write-Host "Scanning config files..."
foreach ($kv in $scanRoots.GetEnumerator()) {
    $site = [string]$kv.Value.site
    $root = [string]$kv.Value.phys

    $files = Get-ChildFilesFast $root $patterns $ExcludeDirs $ExcludeFileSubstrings $maxBytes

    foreach ($f in $files) {
        $map = Map-ToClosestIIS $site $f
        $iisPath = $map.iis
        $itemType = $map.type

        $ext = [IO.Path]::GetExtension($f)
        if ($null -eq $ext) { $ext = "" }
        $ext = $ext.ToLower()

        $found = @()
        if ($ext -eq ".json") { $found = Get-ConnStringsFromJson $f }
        else { $found = Get-ConnStringsFromXml $f }

        foreach ($cs in $found) {
            if (-not $cs.ConnectionString) { continue }
            $conn = Mask-Password ([string]$cs.ConnectionString)
            $cfg  = [string]$cs.ConfigPath

            $k = "$site|$iisPath|$itemType|$cfg|$conn"
            if ($seen.Add($k)) {
                $rows.Add([pscustomobject]@{
                    SiteName         = $site
                    IISPath          = $iisPath
                    ItemType         = $itemType
                    PhysicalPath     = $root
                    BindingProtocol  = ""
                    BindingHost      = ""
                    BindingPort      = ""
                    EndpointUrl      = ""
                    ConfigPath       = $cfg
                    ConnectionString = $conn
                }) | Out-Null
            }
        }
    }
}

# Re-export final output
$rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Host "Updated dependency CSV with config/connection strings:" $OutputCsv
Write-Host "Total rows now:" $rows.Count
