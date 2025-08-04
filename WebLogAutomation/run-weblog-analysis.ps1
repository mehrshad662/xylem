# === WebLog Expert Automation Script for "MeroProject" ===

# Sökväg till WebLog Expert CLI
$weblogExe = "C:\Program Files (x86)\WebLog Expert\WLExpert.exe"

# Profilnamn
$profile = "MeroProject"

# Mapp där rapporten ska sparas
$reportPath = "D:\Reports\MeroProject_Weekly"

# Skapa rapportmappen om den inte finns
if (-not (Test-Path -Path $reportPath)) {
    New-Item -ItemType Directory -Path $reportPath
    Write-Host " Skapade rapportmapp: $reportPath"
}

# Kör WebLog Expert
Write-Host " Kör WebLog Expert för profil: $profile"
& "$weblogExe" "$profile" -r"$reportPath" -s -FromScheduler

Write-Host " WebLog Expert-kommando kördes. Rapporten finns i: $reportPath"
