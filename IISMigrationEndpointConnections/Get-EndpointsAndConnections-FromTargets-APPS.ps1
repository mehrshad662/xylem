# Get-EndpointsAndConnections-FromTargets-APPS.ps1
# PowerShell 5.1 compatible
# ONE report: WCF endpoints (+ .svc/.asmx) + DB connection strings from web*.config

param(
    [Parameter(Mandatory=$true)]
    [string]$SiteName,                # e.g. apps.xylem.net (label for output)

    [Parameter(Mandatory=$true)]
    [string]$TargetsCsv,              # e.g. C:\IISMigrate\IIS_Targets_apps.csv

    [string]$OutCsv = "",             # e.g. C:\IISMigrate\Apps_EndpointsConnections.csv

    [string[]]$Hostnames = $null,     # to build absolute URLs for relative addresses
    [ValidateSet("http","https")]
    [string]$Protocol = "https",

    [switch]$RevealSecrets,           # mask passwords unless set

    [string]$ConfigPattern = "web*.config"   # DEV: use "*.config" if needed
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutCsv)) {
    $safe = ($SiteName -replace '\W','_')
    $OutCsv = "C:\IISMigrate\EndpointsConnections_{0}.csv" -f $safe
}
if ($Hostnames -eq $null -or $Hostnames.Count -eq 0) { $Hostnames = @($SiteName) }

# ensure output folder
$dir = Split-Path -Path $OutCsv -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

# read targets
if (-not (Test-Path $TargetsCsv)) { throw "Targets CSV not found: $TargetsCsv" }
$targets = Import-Csv -Path $TargetsCsv

# -------- helpers --------
function Join-WebPath {
    param([string]$a, [string]$b)
    if ($null -eq $a) { $a = "" }
    if ($null -eq $b) { $b = "" }
    $left  = ($a -replace '/+$','')
    $right = ($b -replace '^/+','')
    if ([string]::IsNullOrWhiteSpace($left)) { return "/$right" }
    if ([string]::IsNullOrWhiteSpace($right)) { return $left }
    return "$left/$right"
}

function Make-FullUrls {
    param([string]$Address,[string[]]$Hostnames,[string]$Protocol,[string]$AppPath)
    $urls = @()
    if ($Address -ne $null -and $Address -match '^(https?|net\.tcp|net\.pipe)://') {
        $urls += $Address
        return $urls
    }
    $rel = ""
    if ($Address -ne $null) { $rel = ($Address -replace '^[~/]+','') }
    $base = $AppPath
    if ($null -eq $base) { $base = "" }
    $base = ($base -replace '/+$','')
    $webPath = if ([string]::IsNullOrWhiteSpace($rel)) { $base } else { Join-WebPath $base $rel }
    if (-not $webPath.StartsWith("/")) { $webPath = "/$webPath" }
    foreach ($h in $Hostnames) {
        $urls += ("{0}://{1}{2}" -f $Protocol, $h, $webPath)
    }
    return $urls
}

function Test-IsConnLike {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    $pat = '(?i)(Data Source|Server|Initial Catalog|Database|User Id|Uid|Password|Pwd|Integrated Security|Trusted_Connection|SERVICE_NAME|SID|HOST=|PORT=|Oracle)'
    return ($s -match $pat)
}

function Guess-DbType {
    param([string]$provider,[string]$cs)
    if (-not [string]::IsNullOrWhiteSpace($provider)) {
        if ($provider -match '(?i)oracle') { return 'Oracle' }
        if ($provider -match '(?i)(sqlclient|system\.data\.sqlclient)') { return 'SQLServer' }
    }
    if (-not [string]::IsNullOrWhiteSpace($cs)) {
        if ($cs -match '(?i)(SERVICE_NAME|SID|HOST=.+;PORT=|User Id=|Uid=|Oracle)') { return 'Oracle' }
        if ($cs -match '(?i)(Server=|Data Source=|Initial Catalog=|Integrated Security=|Trusted_Connection=)') { return 'SQLServer' }
    }
    return 'Unknown'
}

function Mask-Conn {
    param([string]$s, [switch]$Reveal)
    if ($Reveal) { return $s }
    $m = $s
    $m = [regex]::Replace($m, '(?i)(password\s*=\s*)[^;]*', '$1****')
    $m = [regex]::Replace($m, '(?i)(pwd\s*=\s*)[^;]*', '$1****')
    return $m
}
# -------------------------

$rows = New-Object System.Collections.Generic.List[object]

foreach ($t in $targets) {
    $targetType   = $t.TargetType
    $iisPath      = $t.IISPath
    $name         = $t.Name
    $physicalPath = $t.PhysicalPath
    $site         = $t.Site

    if (-not (Test-Path $physicalPath)) {
        $rows.Add([pscustomobject]@{
            Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
            Type="None"; EndpointKind=""; EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
            ConfigPath=""; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString=""; Error="PhysicalPathNotFound"
        })
        continue
    }

    # configs for this target
    $configs = Get-ChildItem -Path $physicalPath -Filter $ConfigPattern -File -ErrorAction SilentlyContinue
    if (-not $configs -or $configs.Count -eq 0) {
        $rows.Add([pscustomobject]@{
            Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
            Type="None"; EndpointKind=""; EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
            ConfigPath=""; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString=""; Error="ConfigNotFound"
        })
    }

    foreach ($cfg in $configs) {
        # parse XML
        $xml = $null
        try {
            $text = Get-Content -Path $cfg.FullName -Raw -ErrorAction Stop
            $xml  = New-Object System.Xml.XmlDocument
            $xml.PreserveWhitespace = $true
            $xml.LoadXml($text)
        } catch {
            $rows.Add([pscustomobject]@{
                Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                Type="None"; EndpointKind=""; EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
                ConfigPath=$cfg.FullName; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString="";
                Error="ConfigParseError"
            })
            continue
        }

        # --- WCF service endpoints ---
        $serviceEndpoints = $xml.SelectNodes("//configuration/system.serviceModel/services/service/endpoint")
        if ($serviceEndpoints -ne $null -and $serviceEndpoints.Count -gt 0) {
            foreach ($ep in $serviceEndpoints) {
                $addr     = if ($ep.Attributes["address"]) { $ep.Attributes["address"].Value } else { "" }
                $binding  = if ($ep.Attributes["binding"]) { $ep.Attributes["binding"].Value } else { "" }
                $contract = if ($ep.Attributes["contract"]) { $ep.Attributes["contract"].Value } else { "" }

                $urls = Make-FullUrls -Address $addr -Hostnames $Hostnames -Protocol $Protocol -AppPath $iisPath
                if ($urls.Count -eq 0) { $urls = @("") }

                foreach ($u in $urls) {
                    $UrlHost = ""
                    if (-not [string]::IsNullOrWhiteSpace($u)) { $UrlHost = ($u -replace '^[a-z]+://','').Split('/')[0] }
                    $rows.Add([pscustomobject]@{
                        Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                        Type="Endpoint"; EndpointKind="services/service/endpoint";
                        EndpointAddr=$u; EndpointHostName=$UrlHost; Binding=$binding; Contract=$contract;
                        ConfigPath=$cfg.FullName; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString=""; Error=""
                    })
                }
            }
        }

        # --- WCF client endpoints ---
        $clientEndpoints = $xml.SelectNodes("//configuration/system.serviceModel/client/endpoint")
        if ($clientEndpoints -ne $null -and $clientEndpoints.Count -gt 0) {
            foreach ($ep in $clientEndpoints) {
                $addr     = if ($ep.Attributes["address"]) { $ep.Attributes["address"].Value } else { "" }
                $binding  = if ($ep.Attributes["binding"]) { $ep.Attributes["binding"].Value } else { "" }
                $contract = if ($ep.Attributes["contract"]) { $ep.Attributes["contract"].Value } else { "" }

                $urls = Make-FullUrls -Address $addr -Hostnames $Hostnames -Protocol $Protocol -AppPath $iisPath
                if ($urls.Count -eq 0) { $urls = @("") }

                foreach ($u in $urls) {
                    $UrlHost = ""
                    if (-not [string]::IsNullOrWhiteSpace($u)) { $UrlHost = ($u -replace '^[a-z]+://','').Split('/')[0] }
                    $rows.Add([pscustomobject]@{
                        Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                        Type="Endpoint"; EndpointKind="client/endpoint";
                        EndpointAddr=$u; EndpointHostName=$UrlHost; Binding=$binding; Contract=$contract;
                        ConfigPath=$cfg.FullName; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString=""; Error=""
                    })
                }
            }
        }

        # --- connectionStrings/add (any level) ---
        $n1 = $xml.SelectNodes("//configuration//connectionStrings/add")
        if ($n1 -ne $null -and $n1.Count -gt 0) {
            foreach ($n in $n1) {
                $keyName = if ($n.Attributes["name"]) { $n.Attributes["name"].Value } else { "" }
                $csVal   = if ($n.Attributes["connectionString"]) { $n.Attributes["connectionString"].Value } else { "" }
                $prov    = if ($n.Attributes["providerName"]) { $n.Attributes["providerName"].Value } else { "" }

                if (Test-IsConnLike $csVal -or -not [string]::IsNullOrWhiteSpace($prov)) {
                    $dbType = Guess-DbType -provider $prov -cs $csVal
                    $rows.Add([pscustomobject]@{
                        Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                        Type="ConnectionString"; EndpointKind="";
                        EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
                        ConfigPath=$cfg.FullName; Source="connectionStrings/add"; KeyName=$keyName; ProviderName=$prov;
                        DbType=$dbType; ConnectionString=(Mask-Conn -s $csVal -Reveal:$RevealSecrets); Error=""
                    })
                }
            }
        }

        # --- appSettings/add entries that look like connection strings ---
        $n2 = $xml.SelectNodes("//configuration//appSettings/add")
        if ($n2 -ne $null -and $n2.Count -gt 0) {
            foreach ($n in $n2) {
                $keyAttr = $n.Attributes["key"]; if (-not $keyAttr) { $keyAttr = $n.Attributes["name"] }
                $valAttr = $n.Attributes["value"]
                $keyName = if ($keyAttr) { $keyAttr.Value } else { "" }
                $val     = if ($valAttr) { $valAttr.Value } else { "" }

                if (Test-IsConnLike $val) {
                    $dbType = Guess-DbType -provider "" -cs $val
                    $rows.Add([pscustomobject]@{
                        Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                        Type="ConnectionString"; EndpointKind="";
                        EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
                        ConfigPath=$cfg.FullName; Source="appSettings/add"; KeyName=$keyName; ProviderName="";
                        DbType=$dbType; ConnectionString=(Mask-Conn -s $val -Reveal:$RevealSecrets); Error=""
                    })
                }
            }
        }

        # --- any <connectionString> element (singular) ---
        $n3 = $xml.SelectNodes("//*[local-name()='connectionString']")
        if ($n3 -ne $null -and $n3.Count -gt 0) {
            foreach ($n in $n3) {
                $val = $n.InnerText
                if ([string]::IsNullOrWhiteSpace($val)) {
                    $valAttr = $n.Attributes["value"]
                    if ($valAttr) { $val = $valAttr.Value }
                }
                if (Test-IsConnLike $val) {
                    $dbType = Guess-DbType -provider "" -cs $val
                    $rows.Add([pscustomobject]@{
                        Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                        Type="ConnectionString"; EndpointKind="";
                        EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
                        ConfigPath=$cfg.FullName; Source="element:connectionString"; KeyName=""; ProviderName="";
                        DbType=$dbType; ConnectionString=(Mask-Conn -s $val -Reveal:$RevealSecrets); Error=""
                    })
                }
            }
        }
    }

    # --- file-based endpoints: .svc / .asmx ---
    try {
        $svcFiles  = Get-ChildItem -Path $physicalPath -Filter "*.svc"  -File -Recurse -ErrorAction SilentlyContinue
        $asmxFiles = Get-ChildItem -Path $physicalPath -Filter "*.asmx" -File -Recurse -ErrorAction SilentlyContinue
        foreach ($f in ($svcFiles + $asmxFiles)) {
            $rel = $f.FullName.Substring($physicalPath.Length).TrimStart('\') -replace '\\','/'
            $urls = Make-FullUrls -Address $rel -Hostnames $Hostnames -Protocol $Protocol -AppPath $iisPath
            foreach ($u in $urls) {
                $UrlHost = ""
                if (-not [string]::IsNullOrWhiteSpace($u)) { $UrlHost = ($u -replace '^[a-z]+://','').Split('/')[0] }
                $rows.Add([pscustomobject]@{
                    Site=$site; ItemType=$targetType; IISPath=$iisPath; Name=$name; PhysicalPath=$physicalPath;
                    Type="Endpoint"; EndpointKind="file-endpoint";
                    EndpointAddr=$u; EndpointHostName=$UrlHost; Binding=""; Contract="";
                    ConfigPath="(file) $($f.FullName)"; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString=""; Error=""
                })
            }
        }
    } catch { }
}

# -------- exports --------
$base     = [System.IO.Path]::ChangeExtension($OutCsv, $null)
$rawCsv   = "$base`_Combined_raw.csv"
$matchCsv = "$base`_Combined_MATCH.csv"
$allCsv   = "$base`_Combined_AllTargets.csv"

# RAW (comma-delimited)
$rows | Export-Csv -NoTypeInformation -Path $rawCsv

# MATCH (Excel-friendly; locale delimiter)
$rows |
  Where-Object { $_.Error -eq "" -and ( $_.Type -in @("Endpoint","ConnectionString") ) } |
  Select-Object Site, ItemType, IISPath, Name, PhysicalPath,
                Type, EndpointKind, EndpointAddr, EndpointHostName, Binding, Contract,
                ConfigPath, Source, KeyName, ProviderName, DbType, ConnectionString |
  Sort-Object Site, ItemType, Name, IISPath, Type, EndpointKind, EndpointAddr, KeyName |
  Export-Csv -Path $matchCsv -NoTypeInformation -UseCulture

# ALL TARGETS (every app/vdir at least once)
$emit = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $hits = $rows | Where-Object {
        $_.IISPath -eq $t.IISPath -and $_.Name -eq $t.Name -and $_.Error -eq "" -and ( $_.Type -in @("Endpoint","ConnectionString") )
    }
    if ($hits -and $hits.Count -gt 0) {
        foreach ($h in $hits) { $emit.Add($h) }
    } else {
        $emit.Add([pscustomobject]@{
            Site=$t.Site; ItemType=$t.TargetType; IISPath=$t.IISPath; Name=$t.Name; PhysicalPath=$t.PhysicalPath;
            Type="None"; EndpointKind=""; EndpointAddr=""; EndpointHostName=""; Binding=""; Contract="";
            ConfigPath=""; Source=""; KeyName=""; ProviderName=""; DbType=""; ConnectionString=""; Error="NoEndpointsOrConnectionsFound"
        })
    }
}
$emit |
  Select-Object Site, ItemType, IISPath, Name, PhysicalPath,
                Type, EndpointKind, EndpointAddr, EndpointHostName, Binding, Contract,
                ConfigPath, Source, KeyName, ProviderName, DbType, ConnectionString, Error |
  Sort-Object Site, ItemType, Name, IISPath, Type, EndpointKind, EndpointAddr, KeyName |
  Export-Csv -Path $allCsv -NoTypeInformation -UseCulture

Write-Host ""
Write-Host "Exported:"
Write-Host "  RAW            : $rawCsv"
Write-Host "  MATCH          : $matchCsv"
Write-Host "  ALL TARGETS    : $allCsv"
