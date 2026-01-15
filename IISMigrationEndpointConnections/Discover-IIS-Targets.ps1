param(
  [string]$SiteName = "extranetapps.xylem.com",
  [string]$OutCsv   = "C:\IISMigrate\IIS_Targets_$($SiteName).csv"
)

Import-Module WebAdministration -ErrorAction Stop
New-Item -ItemType Directory -Path (Split-Path $OutCsv) -Force | Out-Null

function Expand-Path([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $p }
  try { [Environment]::ExpandEnvironmentVariables($p) } catch { return $p }
}

# ----- Applications -----
$rows = @()
$applications = Get-WebApplication -Site $SiteName | Sort-Object Path
foreach ($app in $applications) {
  $phys = Expand-Path $app.physicalPath
  $rows += [pscustomobject]@{
    Site         = $SiteName
    TargetType   = 'Application'       # enum: Application | SiteRootVDir
    IISPath      = $app.Path           # e.g. /TPI
    Name         = $app.Path.TrimStart('/')
    PhysicalPath = $phys
  }
}

# ----- Site-root VirtualDirectories (robust: cmdlet + fallback) -----
# Preferred: cmdlet (those attached to root application '/')
$rootVDirs = @()
try {
  $allVDirs = Get-WebVirtualDirectory -Site $SiteName -ErrorAction Stop
  $rootVDirs = $allVDirs | Where-Object {
    try { $_.Application -eq '/' } catch { $false }
  }
} catch {}

# Fallback: read directly from config if needed
if (-not $rootVDirs -or $rootVDirs.Count -eq 0) {
  $filter = "system.applicationHost/sites/site[@name='$SiteName']/application[@path='/']/virtualDirectory"
  try {
    $rootVDirs = Get-WebConfigurationProperty -PSPath 'IIS:\' -Filter $filter -Name '.' -ErrorAction Stop
  } catch {}
}

foreach ($vd in $rootVDirs) {
  $vdPath = ''; $vdPhys = ''
  try { $vdPath = $vd.Path } catch { try { $vdPath = $vd.path } catch {} }
  try { $vdPhys = $vd.physicalPath } catch { try { $vdPhys = $vd.Attributes['physicalPath'].Value } catch {} }
  $vdPhys = Expand-Path $vdPhys

  $rows += [pscustomobject]@{
    Site         = $SiteName
    TargetType   = 'SiteRootVDir'      # enum: Application | SiteRootVDir
    IISPath      = '/' + ($vdPath -replace '^/','')  # e.g. /ig_common
    Name         = ($vdPath -replace '^/','')
    PhysicalPath = $vdPhys
  }
}

$rows | Sort-Object TargetType, IISPath | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $OutCsv
Write-Host "Targets exported: $OutCsv  (Apps:$($rows | ? {$_.TargetType -eq 'Application'} | measure).Count  RootVDirs:$($rows | ? {$_.TargetType -eq 'SiteRootVDir'} | measure).Count)"
