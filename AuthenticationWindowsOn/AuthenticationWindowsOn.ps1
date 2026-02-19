# --- IIS Windows Auth ON / Anonymous OFF (Octopus reusable) ---
Import-Module WebAdministration

# Set these via Octopus variables (recommended)
$SiteName = $OctopusParameters["IIS.SiteName"]     # e.g. "appsa-dev.world.fluidtechnology.net"
$AppName  = $OctopusParameters["IIS.AppName"]      # e.g. "TPIAdmin" (leave empty for site root)

if (-not $SiteName) { throw "Missing Octopus variable: IIS.SiteName" }

$psPath = if ([string]::IsNullOrWhiteSpace($AppName)) {
  "IIS:\Sites\$SiteName"
} else {
  "IIS:\Sites\$SiteName\$AppName"
}

# Enable Windows Authentication
Set-WebConfigurationProperty -PSPath $psPath `
  -Filter "system.webServer/security/authentication/windowsAuthentication" `
  -Name "enabled" -Value $true

# Disable Anonymous Authentication
Set-WebConfigurationProperty -PSPath $psPath `
  -Filter "system.webServer/security/authentication/anonymousAuthentication" `
  -Name "enabled" -Value $false

Write-Host "Windows Auth enabled + Anonymous disabled for: $psPath"
