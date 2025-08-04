# Ange sökvägen till IIS loggfiler
$logPath = "C:\inetpub\logs\LogFiles\W3SVC1"

# Ange destinationen på D-enheten där loggarna ska kopieras
$destinationPath = "D:\Loggar\IIS_Logs"

# Om mappen inte finns, skapa den
if (-not (Test-Path -Path $destinationPath)) {
    New-Item -ItemType Directory -Path $destinationPath
}

# Kopiera loggfilerna från IIS-loggmappen till den nya destinationen
Copy-Item -Path "$logPath\*" -Destination $destinationPath -Recurse

# Logga en bekräftelse
Write-Host "Loggfiler har kopierats från $logPath till $destinationPath"
