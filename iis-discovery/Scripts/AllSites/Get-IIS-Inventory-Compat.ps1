<#
.SYNOPSIS
  Export IIS inventory to the "old/compat" CSV schema expected by Discover-IIS-Dependencies-CLEAN.ps1
#>

[CmdletBinding()]
param(
  [string]$OutputCsv = "C:\IISDiscovery\Reports\IIS_Sites_Apps_VDirs.csv"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Ensure-Dir([string]$p){
  $dir = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

function Parse-Binding([string]$bindingInformation){
  $ip=''; $port=''; $hostHeader=''
  if ($bindingInformation -match '^(.*?):(\d+):(.*)$') {
    $ip         = $Matches[1]
    $port       = $Matches[2]
    $hostHeader = $Matches[3]
  }
  @{ ip=$ip; port=$port; host=$hostHeader }
}

function Get-SiteRootPhysicalPath([string]$siteName){
  try {
    $filter = "system.applicationHost/sites/site[@name='$siteName']/application[@path='/']/virtualDirectory[@path='/']"
    $v = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name physicalPath -ErrorAction Stop
    return [string]$v.Value
  } catch { return "" }
}

Ensure-Dir $OutputCsv
Import-Module WebAdministration -ErrorAction Stop

$serverName = $env:COMPUTERNAME
$rows = New-Object System.Collections.Generic.List[object]

$sites = Get-Website
foreach ($site in $sites) {
  $siteName = $site.Name
  $siteId   = $site.Id
  $rootPhys = Get-SiteRootPhysicalPath $siteName

  $bindings = @()
  try { $bindings = $site.Bindings.Collection } catch { $bindings = @() }
  if (-not $bindings) { $bindings = @() }

  foreach ($b in $bindings) {
    $prot = [string]$b.protocol
    $info = Parse-Binding ([string]$b.bindingInformation)
    $bindHost = [string]$info.host
    $bindPort = [string]$info.port

    $endpoint = if ($bindHost) {
      "${prot}://$bindHost" + ($(if($bindPort -and $bindPort -ne '80' -and $bindPort -ne '443'){ ":$bindPort" } else { "" })) + "/"
    } else { "" }

    # ROOT row (compat schema)
    $rows.Add([pscustomobject]@{
      Server             = $serverName
      Site_Name          = $siteName
      Site_Id            = $siteId
      Binding_Protocol   = $prot
      Binding_Host       = $bindHost
      Binding_Port       = $bindPort
      App_Path           = "/"
      App_Physical_Path  = $rootPhys
      VDir_Path          = ""
      VDir_Physical_Path = ""
      Item_Type          = "root"
      Endpoint_Url       = $endpoint
    }) | Out-Null
  }

  # Apps
  $apps = @()
  try { $apps = Get-WebApplication -Site $siteName -ErrorAction SilentlyContinue } catch { $apps = @() }
  foreach ($app in $apps) {
    $appPath = [string]$app.Path
    $appPhys = [string]$app.PhysicalPath

    foreach ($b in $bindings) {
      $prot = [string]$b.protocol
      $info = Parse-Binding ([string]$b.bindingInformation)
      $bindHost = [string]$info.host
      $bindPort = [string]$info.port

      $endpoint = if ($bindHost) {
        "${prot}://$bindHost" + ($(if($bindPort -and $bindPort -ne '80' -and $bindPort -ne '443'){ ":$bindPort" } else { "" })) + ($appPath.TrimEnd('/') + "/")
      } else { "" }

      $rows.Add([pscustomobject]@{
        Server             = $serverName
        Site_Name          = $siteName
        Site_Id            = $siteId
        Binding_Protocol   = $prot
        Binding_Host       = $bindHost
        Binding_Port       = $bindPort
        App_Path           = $appPath
        App_Physical_Path  = $appPhys
        VDir_Path          = ""
        VDir_Physical_Path = ""
        Item_Type          = "app"
        Endpoint_Url       = $endpoint
      }) | Out-Null
    }

    # VDirs for this app
    $vdirs = @()
    try { $vdirs = Get-WebVirtualDirectory -Site $siteName -Application $appPath -ErrorAction SilentlyContinue } catch { $vdirs = @() }
    foreach ($vd in $vdirs) {
      $vdPath = [string]$vd.Path
      $vdPhys = [string]$vd.PhysicalPath

      foreach ($b in $bindings) {
        $prot = [string]$b.protocol
        $info = Parse-Binding ([string]$b.bindingInformation)
        $bindHost = [string]$info.host
        $bindPort = [string]$info.port

        $endpoint = if ($bindHost) {
          "${prot}://$bindHost" + ($(if($bindPort -and $bindPort -ne '80' -and $bindPort -ne '443'){ ":$bindPort" } else { "" })) + ($vdPath.TrimEnd('/') + "/")
        } else { "" }

        $rows.Add([pscustomobject]@{
          Server             = $serverName
          Site_Name          = $siteName
          Site_Id            = $siteId
          Binding_Protocol   = $prot
          Binding_Host       = $bindHost
          Binding_Port       = $bindPort
          App_Path           = $appPath
          App_Physical_Path  = $appPhys
          VDir_Path          = $vdPath
          VDir_Physical_Path = $vdPhys
          Item_Type          = "vdir"
          Endpoint_Url       = $endpoint
        }) | Out-Null
      }
    }
  }
}

$rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Host "Created COMPAT inventory CSV: $OutputCsv"
Write-Host "Rows: $($rows.Count)"
