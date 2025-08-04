<#
.SYNOPSIS
This script extracts virtual directories and web directories from an XML file and exports the details to a CSV file.

.DESCRIPTION
It loads an XML file, extracts relevant data for each virtual directory and web directory, and stores the information in a CSV file.

.EXAMPLE
.\Export-VirtualDirectories.ps1 -xmlFilePath "C:\path\to\your\XMLfile.xml" -csvFilePath "C:\path\to\save\output.csv"

.NOTES
Author: Mehrshad Arshi
Version: 1.1
Change Log:
- Initial version.
- Added logging and proper parameter usage.
#>

param(
    [string]$xmlFilePath = "C:\path\to\your\XMLfile.xml",   # Default value if not provided
    [string]$csvFilePath = "C:\path\to\save\output.csv"    # Default value if not provided
)

# Check if the provided XML file path exists
if (-not (Test-Path $xmlFilePath)) {
    Write-Host "Error: The XML file does not exist at the specified path."
    exit
}

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

# Check if directories were found and extracted
if ($directories.Count -eq 0) {
    Write-Host "No directories were found or extracted from the XML file."
    exit
}

# Export the data to the CSV file
$directories | Export-Csv -Path $csvFilePath -NoTypeInformation

Write-Host "Directories extracted and saved to CSV at $csvFilePath."
