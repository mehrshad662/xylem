# Define the source and destination paths
$sourcePath = "C:\inetpub\logs\LogFiles\W3SVC1"  # Specific directory for W3SVC1
$destinationPath = "\\seemm1app399\WebLogExpertLogs\meroproject"  # Network share destination path

# Get the current date
$currentDate = Get-Date

# Define the date for 3 months ago
$threeMonthsAgo = $currentDate.AddMonths(-3)

# Get all log files in the W3SVC1 directory
$logFiles = Get-ChildItem -Path $sourcePath -Filter "*.log"

# Iterate over each log file
foreach ($file in $logFiles) {
    # Check if the log file is from the last 3 months
    if ($file.LastWriteTime -ge $threeMonthsAgo) {
        # Construct the destination file path
        $destinationFile = Join-Path -Path $destinationPath -ChildPath $file.Name

        # Copy the log file to the destination folder
        Copy-Item -Path $file.FullName -Destination $destinationFile
        Write-Host "Copied: $file to $destinationFile"
    }
}

# Check if there are logs from other W3SVC servers (W3SVC2, W3SVC3, etc.)
$sourcePaths = "C:\inetpub\logs\LogFiles\W3SVC2", "C:\inetpub\logs\LogFiles\W3SVC3", "C:\inetpub\logs\LogFiles\W3SVC4"  # Add more if necessary

foreach ($source in $sourcePaths) {
    $logFiles = Get-ChildItem -Path $source -Filter "*.log"
    foreach ($file in $logFiles) {
        if ($file.LastWriteTime -ge $threeMonthsAgo) {
            $destinationFile = Join-Path -Path $destinationPath -ChildPath $file.Name
            Copy-Item -Path $file.FullName -Destination $destinationFile
            Write-Host "Copied: $file to $destinationFile"
        }
    }
}

Write-Host "Log files copied successfully."
