<#
.SYNOPSIS
  De-duplicate an IIS discovery CSV and keep only ONE root ("/") row per site.

.DESCRIPTION
  This script:
  - Removes exact duplicate rows based on key fields.
  - Collapses ALL root ("/") rows per SiteName into ONE summary row.
  - Leaves non-root (apps/vdirs) rows unchanged.
  - Outputs a clean CSV ready for SharePoint, SQL import, or reporting.

.PARAMETER InputCsv
  Path to the original discovery CSV file.

.PARAMETER OutputCsv
  Path to write the cleaned CSV file.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "C:\IISDiscovery\Scripts\Clean-IIS-Discovery-DedupAndCompactRoot.ps1" `
    -InputCsv  "C:\IISDiscovery\Reports\IIS_Discovery_AllSites_FIXED.csv" `
    -OutputCsv "C:\IISDiscovery\Reports\IIS_Discovery_AllSites_DEDUP_COMPACTROOT.csv"
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv,

  [Parameter(Mandatory = $true)]
  [string]$OutputCsv
)

# ---- Ensure file exists ----
if (-not (Test-Path -LiteralPath $InputCsv)) {
  Write-Error "Input CSV not found: $InputCsv"
  exit 1
}

# ---- Load CSV ----
try {
  $rows = Import-Csv -LiteralPath $InputCsv
} catch {
  Write-Error "Failed to read CSV: $($_.Exception.Message)"
  exit 1
}

if (-not $rows -or $rows.Count -eq 0) {
  Write-Warning "Input CSV is empty. Writing empty output."
  @() | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
  exit 0
}

# ---- Ensure all expected columns exist ----
$expected = @(
  'SiteName','IISPath','ItemType','PhysicalPath','BindingProtocol','BindingHost',
  'BindingPort','EndpointUrl','ConfigPath','ConnectionString'
)

foreach ($r in $rows) {
  foreach ($c in $expected) {
    if (-not ($r.PSObject.Properties.Name -contains $c)) {
      Add-Member -InputObject $r -NotePropertyName $c -NotePropertyValue "" -Force
    }
  }
}

# ---- Remove duplicates ----
$keyCols = @('SiteName','IISPath','ItemType','PhysicalPath','BindingHost','BindingPort','EndpointUrl','ConfigPath','ConnectionString')

$uniqueMap = @{}
$dedupRows = New-Object System.Collections.Generic.List[object]
foreach ($r in $rows) {
  $key = ($keyCols | ForEach-Object { [string]$r.$_ }) -join '¦'
  if (-not $uniqueMap.ContainsKey($key)) {
    $uniqueMap[$key] = $true
    $dedupRows.Add($r)
  }
}

Write-Host "Removed $($rows.Count - $dedupRows.Count) duplicate rows."

# ---- Collapse all root ("/") rows into one per site ----
$rootRows = $dedupRows | Where-Object { $_.IISPath -eq '/' }
$nonRootRows = $dedupRows | Where-Object { $_.IISPath -ne '/' }

$collapsed = New-Object System.Collections.Generic.List[object]

if ($rootRows.Count -gt 0) {
  $rootGroups = $rootRows | Group-Object SiteName

  foreach ($g in $rootGroups) {
    $site = $g.Name
    $items = $g.Group
    $first = $items | Select-Object -First 1

    # Gather endpoint summary
    $endpoints = ($items | ForEach-Object { [string]$_.EndpointUrl } | Where-Object { $_ -and $_.Trim() -ne "" } | Sort-Object -Unique)
    $endpointCount = $endpoints.Count
    $endpointSample = ($endpoints | Select-Object -First 3) -join ', '

    # Gather config summary
    $configFiles = ($items | ForEach-Object {
        $p = [string]$_.ConfigPath
        if ($p -and ($p -match '[\\/]+')) { [System.IO.Path]::GetFileName($p) } else { $p }
      } | Where-Object { $_ -and $_.Trim() -ne "" } | Sort-Object -Unique)
    $cfgCount = $configFiles.Count
    $cfgSample = ($configFiles | Select-Object -First 3) -join ', '
    $connCount = ($items | Where-Object { $_.ConnectionString -and $_.ConnectionString.Trim() -ne "" }).Count

    # Most common physical path
    $physPaths = $items | ForEach-Object { [string]$_.PhysicalPath }
    $physicalPath = ($physPaths | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name

    # Create compact root summary row
    $collapsed.Add([pscustomobject]@{
      SiteName         = $site
      IISPath          = '/'
      ItemType         = 'root'
      PhysicalPath     = $physicalPath
      BindingProtocol  = ''
      BindingHost      = ''
      BindingPort      = ''
      EndpointUrl      = if ($endpointCount -gt 0) { "[root] $endpointCount endpoint(s) (e.g., $endpointSample)" } else { "" }
      ConfigPath       = if ($cfgCount -gt 0) { "[root] $cfgCount config file(s) (e.g., $cfgSample)" } else { "" }
      ConnectionString = if ($connCount -gt 0) { "[root] $connCount connection string(s)" } else { "" }
    })
  }
}

# ---- Combine everything ----
$final = @()
$final += $nonRootRows
$final += $collapsed

# ---- Sort by site and IIS path ----
$final = $final | Sort-Object SiteName, IISPath, ItemType, BindingHost, BindingPort

# ---- Export ----
$final | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Clean report created successfully!"
Write-Host "Input rows: $($rows.Count)"
Write-Host "After deduplication: $($dedupRows.Count)"
Write-Host "Final after compact root: $($final.Count)"
Write-Host "Output: $OutputCsv"
