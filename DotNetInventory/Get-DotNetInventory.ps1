<#
.SYNOPSIS
  Collects installed .NET Framework 4.x and modern .NET (Core / 5+) runtimes
  from a Windows server and writes ONE row to a CSV.

.NOTES
  Octopus-safe: no top-level [CmdletBinding()] and no top-level param().
  Central share is attempted first; if not reachable, writes locally.
#>

Write-Host "DOTNET INVENTORY SCRIPT VERSION = 2026-01-13-v3"

# =========================
# CONFIG (edit if needed)
# =========================
$CentralCsv = "\\46fasapp02.world.fluidtechnology.net\group\Fas-Stockholm\ACRODOC\Mero\DotNetInventory_AllServers.csv"
$LocalCsv   = "C:\Temp\DotNetInventory.csv"

# =========================
# Helpers
# =========================
function Get-DotNetFramework4x {
    $regPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    if (-not (Test-Path $regPath)) {
        return @{ Version = "Not installed"; Release = $null }
    }

    $release = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).Release
    if (-not $release) {
        return @{ Version = "Unknown"; Release = $null }
    }

    $version = switch ($release) {
        { $_ -ge 533325 } { "4.8.1"; break }
        { $_ -ge 528040 } { "4.8";   break }
        { $_ -ge 461808 } { "4.7.2"; break }
        { $_ -ge 461308 } { "4.7.1"; break }
        { $_ -ge 460798 } { "4.7";   break }
        { $_ -ge 394802 } { "4.6.2"; break }
        { $_ -ge 394254 } { "4.6.1"; break }
        { $_ -ge 393295 } { "4.6";   break }
        { $_ -ge 379893 } { "4.5.2"; break }
        { $_ -ge 378675 } { "4.5.1"; break }
        { $_ -ge 378389 } { "4.5";   break }
        default           { "Unknown (Release=$release)" }
    }

    return @{ Version = $version; Release = $release }
}

function Get-DotNetCliRuntimes {
    # We only need versions, keep it simple.
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $cmd) { return @{ Present = $false; Runtimes = "" } }

    $runtimes = (dotnet --list-runtimes 2>$null) -join "; "
    return @{ Present = $true; Runtimes = $runtimes }
}

function Write-ResultToCsv {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [psobject]$Row
    )

    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (Test-Path $Path) {
        $Row | Export-Csv -Path $Path -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $Row | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    }
}

# =========================
# Collect data
# =========================
$fw4 = Get-DotNetFramework4x
$cli = Get-DotNetCliRuntimes

$octoEnv = $env:OctopusEnvironmentName
if ([string]::IsNullOrWhiteSpace($octoEnv)) { $octoEnv = "UNKNOWN" }

# One row per server
$result = [PSCustomObject]@{
    ServerName        = $env:COMPUTERNAME
    Environment       = $octoEnv
    DotNetFramework4x = $fw4.Version
    DotNetRuntimes    = $cli.Runtimes
    CollectedAt       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

# =========================
# Output (central -> local)
# =========================
try {
    $centralDir = Split-Path -Path $CentralCsv -Parent

    if (Test-Path $centralDir) {
        Write-ResultToCsv -Path $CentralCsv -Row $result
        Write-Host "Wrote inventory to CENTRAL CSV: $CentralCsv"
    }
    else {
        Write-ResultToCsv -Path $LocalCsv -Row $result
        Write-Host "Central share not reachable. Wrote LOCAL CSV: $LocalCsv"
    }
}
catch {
    # Never fail the run because of share access
    try {
        Write-ResultToCsv -Path $LocalCsv -Row $result
        Write-Host "Error writing to central share. Wrote LOCAL CSV: $LocalCsv"
        Write-Host "Error: $($_.Exception.Message)"
    }
    catch {
        # Last resort: still don't fail the run
        Write-Host "Failed writing both central and local CSV. Error: $($_.Exception.Message)"
    }
}

# Force success so Octopus doesn't mark the step failed for file-share issues
exit 0
