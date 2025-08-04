# Define the path to the XML file
$xmlFilePath = "C:\Users\MARSHI\Downloads\ExportRepSite\20250416ExportRepSite.xml"

# Load the XML file
[xml]$xml = Get-Content -Path $xmlFilePath

# Define the namespace manager
$namespace = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$namespace.AddNamespace("ns", "urn:microsoft-catalog:XML_Metabase_V64_0")

# Initialize an array to store the directory details
$directories = @()

# Extract and display the <IIsWebVirtualDir> nodes
$virtualDirs = $xml.SelectNodes("//ns:IIsWebVirtualDir", $namespace)
Write-Host "IIsWebVirtualDir nodes found: $($virtualDirs.Count)"

# Loop through each <IIsWebVirtualDir> element to extract relevant information
foreach ($virtualDir in $virtualDirs) {
    if ($virtualDir.Attributes["Location"] -and $virtualDir.Attributes["AppFriendlyName"] -and $virtualDir.Attributes["Path"]) {
        $dirName = $virtualDir.Attributes["Location"].Value
        $webDirName = $virtualDir.Attributes["AppFriendlyName"].Value
        $physicalPath = $virtualDir.Attributes["Path"].Value

        # Store the data in an array
        $directories += [PSCustomObject]@{
            DirectoryName  = $dirName
            WebDirectory   = $webDirName
            PhysicalPath   = $physicalPath
        }
    }
}

# Extract and display the <IIsWebDirectory> nodes
$webDirs = $xml.SelectNodes("//ns:IIsWebDirectory", $namespace)
Write-Host "IIsWebDirectory nodes found: $($webDirs.Count)"

# Loop through each <IIsWebDirectory> element to extract relevant information
foreach ($webDir in $webDirs) {
    if ($webDir.Attributes["Location"] -and $webDir.Attributes["AppFriendlyName"] -and $webDir.Attributes["Path"]) {
        $dirName = $webDir.Attributes["Location"].Value
        $webDirName = $webDir.Attributes["AppFriendlyName"].Value
        $physicalPath = $webDir.Attributes["Path"].Value

        # Store the data in an array
        $directories += [PSCustomObject]@{
            DirectoryName  = $dirName
            WebDirectory   = $webDirName
            PhysicalPath   = $physicalPath
        }
    }
}

# Define the output CSV file path
$csvFilePath = "C:\Users\MARSHI\Downloads\ExportRepSite\virtual_directories.csv"

# Export the data to the CSV file
$directories | Export-Csv -Path $csvFilePath -NoTypeInformation

Write-Host "Directories extracted and saved to CSV at $csvFilePath."
