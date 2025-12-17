# === Mask-ConnectionStrings.ps1 ===
function Mask-ConnString {
    param([string]$ConnString)

    if (-not $ConnString) { return $ConnString }

    # Replace any password or pwd= value with **** (case-insensitive)
    return ($ConnString -replace '(?i)(pwd|password)\s*=\s*([^;]+)', '$1=****')
}
