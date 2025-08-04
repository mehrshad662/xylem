<# 
.SYNOPSIS
update-server.ps1 - Server Update Script
		 
.DESCRIPTION
A PowerShell script to download tools and set up a workstation.
		 
I need to add more info in here.
		 
.EXAMPLE
.\IISLogsCleanup.ps1 -Logpath "D:\IIS Logs\W3SVC1"
This example will compress the log files in "D:\IIS Logs\W3SVC1" and leave
the zip files in that location.
		 
.EXAMPLE
.\update-server.ps1
		 
.NOTES
Written by: Eric Sanders
		 
Change Log
V1.00, 12/9/2020
#>
try
{
    Import-Module XylemModule #imports module for logging functions
    write-host "successfully loaded XylemModule"
}
catch
{
    write-host "could not load XylemModule - exiting script"
    if ($($_.exception.message) -eq "NuGet provider is required to interact with NuGet-based repositories. Please ensure that '2.8.5.201' or newer version of NuGet provider is installed.")
    {
        write-host "this is where i would install nuget package" ########### NEEDS UPDATE ###########
    }
    exit
}
$logfile = "D:\Log\update-server.log" #specify logfile location
$iislog = "D:\inetpub\Logs\logfiles"

if (!(Test-Path $logfile)) #if no log file, create one
{
    New-Item -path $logfile -Force
    New-XylemLogWrite -logfile $logfile -linevalue "log file did not exist, so i created it."
}
Start-XylemLogCreate -logfile $logfile

###########################################################################
################################ FUNCTIONS ################################
###########################################################################
Function AddPermissionsForSvcWebservice
{   Param
    (
        [Parameter(Mandatory=$true)][string]$logfile
    )
	Process 
	{
		New-XylemLogWrite -logfile $logfile -linevalue "Starting $($MyInvocation.MyCommand.Name)"
		
		try
		{
			$user = "World\svc-webservice"
			foreach($LogLocation in $iislog)
			{
				#Get current Acl
				$Acl = Get-Acl $LogLocation
				#Add rights for "world\svc-webservice"
				$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($user,"Modify","Allow")
				$Acl.SetAccessRule($Ar)
				try
				{
					Set-Acl $LogLocation $Acl
                    New-XylemLogWrite -logfile $logfile -linevalue "Set-acl: $loglocation, $acl"
				}
				catch
				{
					New-XylemLogError -logfile $logfile -errordesc "$_.Exception.Message"
				}
				try
				{
					Get-ChildItem -Path $LogLocation -Recurse -Force | Set-Acl -AclObject $Acl
				}
				catch
				{
					New-XylemLogError -logfile $logfile -errordesc "$_.Exception.Message"
				}
				
			}
		}
		catch
		{
			New-XylemLogError -logfile $logfile -errordesc "$_.Exception.Message" 
		}
		New-XylemLogWrite -logfile $logfile -linevalue "Ending function $($MyInvocation.MyCommand.Name)"
	}
}
Function Set-PageFile
{
<#
    .SYNOPSIS
        Set-PageFile is an advanced function which can be used to adjust virtual memory page file size.
    .DESCRIPTION
        Set-PageFile is an advanced function which can be used to adjust virtual memory page file size.
    .PARAMETER  <InitialSize>
        Setting the paging file's initial size.
    .PARAMETER  <MaximumSize>
        Setting the paging file's maximum size.
    .PARAMETER  <DriveLetter>
        Specifies the drive letter you want to configure.
    .PARAMETER  <SystemManagedSize>
        Allow Windows to manage page files on this computer.
    .PARAMETER  <None>        
        Disable page files setting.
    .PARAMETER  <Reboot>      
        Reboot the computer so that configuration changes take effect.
    .PARAMETER  <AutoConfigure>
        Automatically configure the initial size and maximumsize.
    .EXAMPLE
        C:\PS> Set-PageFile -InitialSize 1024 -MaximumSize 2048 -DriveLetter "C:","D:"
 
        Execution Results: Set page file size on "C:" successful.
        Execution Results: Set page file size on "D:" successful.
 
        Name            InitialSize(MB) MaximumSize(MB)
        ----            --------------- ---------------
        C:\pagefile.sys            1024            2048
        D:\pagefile.sys            1024            2048
        E:\pagefile.sys            2048            2048
    .LINK
        Get-WmiObject
        http://technet.microsoft.com/library/hh849824.aspx#>
    [cmdletbinding(SupportsShouldProcess,DefaultParameterSetName="SetPageFileSize")]
    Param
    (
        [Parameter(Mandatory,ParameterSetName="SetPageFileSize")]
        [Alias('is')]
        [Int32]$InitialSize,
 
        [Parameter(Mandatory,ParameterSetName="SetPageFileSize")]
        [Alias('ms')]
        [Int32]$MaximumSize,
 
        [Parameter(Mandatory)]
        [Alias('dl')]
        [ValidatePattern('^[A-Z]$')]
        [String[]]$DriveLetter,
 
        [Parameter(Mandatory,ParameterSetName="None")]
        [Switch]$None,
 
        [Parameter(Mandatory,ParameterSetName="SystemManagedSize")]
        [Switch]$SystemManagedSize,
 
        [Parameter()]
        [Switch]$Reboot,
 
        [Parameter(Mandatory,ParameterSetName="AutoConfigure")]
        [Alias('auto')]
        [Switch]$AutoConfigure,

        [Parameter(Mandatory=$true)][string]$logfile
    )
    Begin {}
    Process 
    {
        If($PSCmdlet.ShouldProcess("Setting the virtual memory page file size")) 
        {
            $DriveLetter | ForEach-Object -Process {
            New-XylemLogWrite -logfile $logfile -linevalue "Starting PageFile"
                $DL = $_
                $PageFile = $Vol = $null
                try 
                {
                    $Vol = Get-CimInstance -ClassName CIM_StorageVolume -Filter "Name='$($DL):\\'" -ErrorAction Stop
                    New-XylemLogWrite -logfile $logfile -linevalue "Name=$($DL)"
                } 
                catch 
                {
                    Write-Warning -Message "Failed to find the DriveLetter $DL specified"
                    New-XylemLogError -logfile $logfile -errordesc "Failed to find the DriveLetter $DL specified"
                    return
                }
                if ($Vol.DriveType -ne 3) 
                {
                    Write-Warning -Message "The selected drive should be a fixed local volume"
                    New-XylemLogError -logfile $logfile -errordesc "The selected drive should be a fixed local volume"
                    return
                }
                Switch ($PsCmdlet.ParameterSetName) 
                {
                    None 
                    {
                        try 
                        {
                            $PageFile = Get-CimInstance -Query "Select * From Win32_PageFileSetting Where Name='$($DL):\\pagefile.sys'" -ErrorAction Stop
                            New-XylemLogWrite -logfile $logfile -linevalue "Pagefile:$Pagefile"
                        } 
                        catch 
                        {
                            Write-Warning -Message "Failed to query the Win32_PageFileSetting class because $($_.Exception.Message)"
                            New-XylemLogError -logfile $logfile -errordesc "Failed to query the Win32_PageFileSetting class because $($_.Exception.Message)"
                        }
                        If($PageFile) 
                        {
                            try 
                            {
                                $PageFile | Remove-CimInstance -ErrorAction Stop 
                                New-XylemLogWrite -logfile $logfile -linevalue "Deleted pagefile from pagefilesetting class"
                            } 
                            catch 
                            {
                                Write-Warning -Message "Failed to delete pagefile the Win32_PageFileSetting class because $($_.Exception.Message)"
                                New-XylemLogError -logfile $logfile -errordesc "Failed to delete pagefile the Win32_PageFileSetting class because $($_.Exception.Message)"
                            }
                        } 
                        Else 
                        {
                            Write-Warning "$DL is already set None!"
                            New-XylemLogError -logfile $logfile -errordesc "$DL is already set None!"
                        }
                        break
                    }
                    SystemManagedSize 
                    {
                        Set-PageFileSize -logfile $logfile -DL $DL -InitialSize 0 -MaximumSize 0
                        break
                    }
                    AutoConfigure 
                    {         
                        $TotalPhysicalMemorySize = @()
                        #Getting total physical memory size
                        try 
                        {
                            Get-CimInstance Win32_PhysicalMemory  -ErrorAction Stop | ? DeviceLocator -ne "SYSTEM ROM" | ForEach-Object 
                            {
                                $TotalPhysicalMemorySize += [Double]($_.Capacity)/1GB
                            }
                        } 
                        catch 
                        {
                            Write-Warning -Message "Failed to query the Win32_PhysicalMemory class because $($_.Exception.Message)"
                            New-XylemLogError -logfile $logfile -errordesc "Failed to query the Win32_PhysicalMemory class because $($_.Exception.Message)"
                        }       
                        <#
                        By default, the minimum size on a 32-bit (x86) system is 1.5 times the amount of physical RAM if physical RAM is less than 1 GB, 
                        and equal to the amount of physical RAM plus 300 MB if 1 GB or more is installed. The default maximum size is three times the amount of RAM, 
                        regardless of how much physical RAM is installed. 
                        If($TotalPhysicalMemorySize -lt 1) {
                            $InitialSize = 1.5*1024
                            $MaximumSize = 1024*3
                            Set-PageFileSize -DL $DL -InitialSize $InitialSize -MaximumSize $MaximumSize
                        } Else {
                            $InitialSize = 1024+300
                            $MaximumSize = 1024*3
                            Set-PageFileSize -DL $DL -InitialSize $InitialSize -MaximumSize $MaximumSize
                        }
                        #>
 
 
                        $InitialSize = (Get-CimInstance -ClassName Win32_PageFileUsage).AllocatedBaseSize
                        $sum = $null
                        (Get-Counter '\Process(*)\Page File Bytes Peak' -SampleInterval 15 -ErrorAction SilentlyContinue).CounterSamples.CookedValue | % {$sum += $_}
                        $MaximumSize = ($sum*70/100)/1MB
                        if ($Vol.FreeSpace -gt $MaximumSize) 
                        {
                            Set-PageFileSize -logfile $logfile -DL $DL -InitialSize $InitialSize -MaximumSize $MaximumSize
                        } 
                        else 
                        {
                            Write-Warning -Message "Maximum size of page file being set exceeds the freespace available on the drive"
                            New-XylemLogError -logfile $logfile -errordesc "Maximum size of page file being set exceeds the freespace available on the drive"
                        }
                        break
                                 
                    }
                    Default 
                    {
                        if ($Vol.FreeSpace -gt $MaximumSize) 
                        {
                            Set-PageFileSize -logfile $logfile -DL $DL -InitialSize $InitialSize -MaximumSize $MaximumSize
                        } 
                        else 
                        {
                            Write-Warning -Message "Maximum size of page file being set exceeds the freespace available on the drive"
                            New-XylemLogError -logfile $logfile -errordesc "Maximum size of page file being set exceeds the freespace available on the drive"
                        }
                    }
                }
            }
 
            # Get current page file size information
            try 
            {
            Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction Stop |Select-Object Name,
            @{Name="InitialSize(MB)";Expression={if($_.InitialSize -eq 0){"System Managed"}else{$_.InitialSize}}}, 
            @{Name="MaximumSize(MB)";Expression={if($_.MaximumSize -eq 0){"System Managed"}else{$_.MaximumSize}}}| 
            Format-Table -AutoSize
            } 
            catch 
            {
                Write-Warning -Message "Failed to query Win32_PageFileSetting class because $($_.Exception.Message)"
                New-XylemLogError -logfile $logfile -errordesc "Failed to query Win32_PageFileSetting class because $($_.Exception.Message)"
            }
            If($Reboot) 
            {
                Restart-Computer -ComputerName $Env:COMPUTERNAME -Force
            }
        }
        New-XylemLogWrite -logfile $logfile -linevalue "Ending Pagefile"
    }
    End {}
}
 
Function Set-PageFileSize {
[CmdletBinding()]
Param(
        [Parameter(Mandatory)]
        [Alias('dl')]
        [ValidatePattern('^[A-Z]$')]
        [String]$DriveLetter,
 
        [Parameter(Mandatory)]
        [ValidateRange(0,[int32]::MaxValue)]
        [Int32]$InitialSize,
 
        [Parameter(Mandatory)]
        [ValidateRange(0,[int32]::MaxValue)]
        [Int32]$MaximumSize,

        [Parameter(Mandatory=$true)][string]$logfile
)
Begin {}
Process {
    #The AutomaticManagedPagefile property determines whether the system managed pagefile is enabled. 
    #This capability is not available on windows server 2003,XP and lower versions.
    #Only if it is NOT managed by the system and will also allow you to change these.
    try {
        $Sys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop 
    } catch {
         
    }
    New-XylemLogWrite -logfile $logfile -linevalue "Starting PageFileSize"
    If($Sys.AutomaticManagedPagefile) {
        try {
            $Sys | Set-CimInstance -Property @{ AutomaticManagedPageFile = $false } -ErrorAction Stop
            Write-Verbose -Message "Set the AutomaticManagedPageFile to false"
            New-XylemLogWrite -logfile $logfile -linevalue "Set the AutomaticManagedPageFile to false"
        } catch {
            Write-Warning -Message "Failed to set the AutomaticManagedPageFile property to false in  Win32_ComputerSystem class because $($_.Exception.Message)"
            New-XylemLogError -logfile $logfile -errordesc "Failed to set the AutomaticManagedPageFile property to false in  Win32_ComputerSystem class because $($_.Exception.Message)"
        }
    }
     
    # Configuring the page file size
    try {
        $PageFile = Get-CimInstance -ClassName Win32_PageFileSetting -Filter "SettingID='pagefile.sys @ $($DriveLetter):'" -ErrorAction Stop
        New-XylemLogWrite -logfile $logfile -linevalue "Pagefile:$Pagefile"
    } catch {
        Write-Warning -Message "Failed to query Win32_PageFileSetting class because $($_.Exception.Message)"
        New-XylemLogError -logfile $logfile -errordesc "Failed to query Win32_PageFileSetting class because $($_.Exception.Message)"
    }
 
    If($PageFile){
        try {
            $PageFile | Remove-CimInstance -ErrorAction Stop
        } catch {
            Write-Warning -Message "Failed to delete pagefile the Win32_PageFileSetting class because $($_.Exception.Message)"
            New-XylemLogError -logfile $logfile -errordesc "Failed to delete pagefile the Win32_PageFileSetting class because $($_.Exception.Message)"
        }
    }
    try {
        New-CimInstance -ClassName Win32_PageFileSetting -Property  @{Name= "$($DriveLetter):\pagefile.sys"} -ErrorAction Stop | Out-Null
      
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa394245%28v=vs.85%29.aspx            
        Get-CimInstance -ClassName Win32_PageFileSetting -Filter "SettingID='pagefile.sys @ $($DriveLetter):'" -ErrorAction Stop | Set-CimInstance -Property @{
            InitialSize = $InitialSize ;
            MaximumSize = $MaximumSize ; 
        } -ErrorAction Stop
         
        Write-Verbose -Message "Successfully configured the pagefile on drive letter $DriveLetter"
        New-XylemLogWrite -logfile $logfile -linevalue "Successfully configured the pagefile on drive letter $DriveLetter"
 
    } catch 
    {
        Write-Warning "Pagefile configuration changed on computer '$Env:COMPUTERNAME'. The computer must be restarted for the changes to take effect."
        New-XylemLogError -logfile $logfile -errordesc "Pagefile configuration changed on computer '$Env:COMPUTERNAME'. The computer must be restarted for the changes to take effect."
    }
}
End {}
}
function Change-DVDDrvLetter #if E change to D
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$logfile
    )
    $NewDVDDrvLetter = "K:"
    $NewAppDrvLetter = "D:"

    # Get Available CD/DVD Drive - Drive Type 5
    $DvdDrv = Get-WmiObject -Class Win32_Volume -Filter "DriveType=5"
 
    # Check if CD/DVD Drive is Available
    if ($DvdDrv -ne $null)
    {
	    # Get Current Drive Letter for CD/DVD Drive
	    $DvdDrvLetter = $DvdDrv | Select-Object -ExpandProperty DriveLetter
	    New-XylemLogWrite -logfile $logfile -linevalue "Current CD/DVD Drive Letter is $DvdDrvLetter"
	 
	    # Confirm New Drive Letter is NOT used
	    if (-not (Test-Path -Path $NewDVDDrvLetter))
	    {
		    # Change CD/DVD Drive Letter
		    $DvdDrv | Set-WmiInstance -Arguments @{DriveLetter="$NewDVDDrvLetter"}
		    New-XylemLogWrite -logfile $logfile -linevalue "Updated CD/DVD Drive Letter as $NewDVDDrvLetter"
	    }
	    else
	    {
		    New-XylemLogError -logfile $logfile -errordesc "Error: Drive Letter $NewDVDDrvLetter Already In Use"
	    }
    }
    else
    {
	    New-XylemLogWrite -logfile $logfile -linevalue "Error: No CD/DVD Drive Available !!"
    }

    # Get tha application drive
    $AppDrv = Get-WmiObject -Class Win32_Volume | Where-Object{$_.Label -eq "APP_Drive"}
    if ($AppDrv -ne $null)
    {
	    # Get Current Drive Letter for Application Drive
	    $AppDrvLetter = $AppDrv | Select-Object -ExpandProperty DriveLetter
	    New-XylemLogWrite -logfile $logfile -linevalue "Current Application Drive Letter is $AppDrvLetter"
	 
	    # Confirm New Drive Letter is NOT used
	    if (-not (Test-Path -Path $NewAppDrvLetter))
	    {
		    # Change Application Drive Letter
		    $AppDrv | Set-WmiInstance -Arguments @{DriveLetter="$NewAppDrvLetter"}
            New-XylemLogWrite -logfile $logfile -linevalue "Updated Application Drive Letter as $NewAppDrvLetter"
	    }
	    else
	    {
            New-XylemLogError -logfile $logfile -errordesc "Error: Drive Letter $NewAppDrvLetter Already In Use"
	    }
    }
}
function IIScheck
{
    install-windowsfeature -name Web-Server -includeallsubfeature
    install-windowsfeature -name Web-WebServer -includeallsubfeature
    install-windowsfeature -name Web-Common-Http-Errors -includeallsubfeature
    install-windowsfeature -name Web-Default-Doc -includeallsubfeature
    install-windowsfeature -name Web-Dir-Browsing -includeallsubfeature
    install-windowsfeature -name Web-Http-Errors -includeallsubfeature
    install-windowsfeature -name Web-Static-Content -includeallsubfeature
    install-windowsfeature -name Web-Http-Redirect -includeallsubfeature
    install-windowsfeature -name Web-Http-Logging -includeallsubfeature
    install-windowsfeature -name Web-Log-Libraries -includeallsubfeature
    install-windowsfeature -name Web-Performance -includeallsubfeature
    install-windowsfeature -name Web-Stat-Compression -includeallsubfeature
    install-windowsfeature -name Web-Security -includeallsubfeature
    install-windowsfeature -name Web-Filtering -includeallsubfeature
    install-windowsfeature -name Web-Basic-Auth -includeallsubfeature
    install-windowsfeature -name Web-certProvider -includeallsubfeature
    install-windowsfeature -name Web-Windows-Auth -includeallsubfeature
    install-windowsfeature -name Web-Mgmt-Tools -includeallsubfeature
    install-windowsfeature -name Web-Mgmt-Console -includeallsubfeature
    install-windowsfeature -name Web-Scripting-Tools -includeallsubfeature
    install-windowsfeature -name Telnet-Client -includeallsubfeature
}

###############################################################################
################################ END FUNCTIONS ################################
###############################################################################

###############################################################################
############################### TEST AREA #####################################
###############################################################################
$tools = "\\46fasapp02\group\Fas-Stockholm\Webmaster\Tools"
$localtools = "D:\temp\tools"

if (!(Test-Path $localtools)) #if no tools location exists, create one
{
    New-Item -ItemType Directory -path $localtools -Force
    New-XylemLogWrite -logfile $logfile -linevalue "$localtools did not exist, so i created it."
}
else
{
    New-XylemLogWrite -logfile $logfile -linevalue "$localtools existed - moving on."
}
#copy files locally first
$localnpp = "D:\temp\tools\npp.7.9.1.Installer.x64.exe"
$localbcompare = "D:\temp\tools\BCompare-4.2.10.23938.exe"
$localwebplatforminstaller = "D:\temp\tools\WebPlatformInstaller_x64_en-US.msi"
$localurlrewrite = "D:\temp\tools\rewrite_amd64_en-US.msi"
$localtree = "D:\temp\tools\TreeSizeFreeSetup.exe"

#make sure they don't already exist
if (!(test-path $localtree))
{
    copy-item \\46fasapp02\group\Fas-Stockholm\Webmaster\Tools\TreeSizeFreeSetup.exe D:\temp\tools
    New-XylemLogWrite -logfile $logfile -linevalue "Local treesize not found: copying from $tools"
}
else
{
    New-XylemLogWrite -logfile $logfile -linevalue "Local treesize found: No copy needed"
}
if (!(test-path $localnpp))
{
    copy-item \\46fasapp02\group\Fas-Stockholm\Webmaster\Tools\npp.7.9.1.Installer.x64.exe D:\temp\tools
    New-XylemLogWrite -logfile $logfile -linevalue "Local NPP not found: copying from $tools"
}
else
{
    New-XylemLogWrite -logfile $logfile -linevalue "Local NPP found: No copy needed"
}
if (!(test-path $localbcompare))
{
    copy-item \\46fasapp02\group\Fas-Stockholm\Webmaster\Tools\BCompare-4.2.10.23938.exe D:\temp\tools
    New-XylemLogWrite -logfile $logfile -linevalue "Local bcompare not found: copying from $tools"
}
else
{
    New-XylemLogWrite -logfile $logfile -linevalue "Local bcompare found: No copy needed"
}
if (!(test-path $localwebplatforminstaller))
{
    copy-item \\46fasapp02\group\Fas-Stockholm\Webmaster\Tools\WebPlatformInstaller_x64_en-US.msi D:\temp\tools
    New-XylemLogWrite -logfile $logfile -linevalue "Local web platform installer not found: copying from $tools"
}
else
{
    New-XylemLogWrite -logfile $logfile -linevalue "Local web platform installer found: No copy needed"
}
if (!(test-path $localurlrewrite))
{
    copy-item \\46fasapp02\group\Fas-Stockholm\Webmaster\Tools\rewrite_amd64_en-US.msi D:\temp\tools
    New-XylemLogWrite -logfile $logfile -linevalue "Local url rewrite not found: copying from $tools"
}
else
{
    New-XylemLogWrite -logfile $logfile -linevalue "Local url rewrite found: No copy needed"
}


###############################################################################
################################  MAIN CODE  ##################################
###############################################################################

New-XylemLogWrite -logfile $logfile -linevalue "Starting Multiple RDP Session function"
#enable Multiple RDP Session - from multiple rdp session script
set-itemproperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -name fSingleSessionPerUser -Value 0

#from permissions script
AddPermissionsForSvcWebservice -logfile $logfile -verbose #-settingsFile "c:\bin\Configs\Configuration.xml"

New-XylemLogWrite -logfile $logfile -linevalue "Set-PageFiletoP"
# from setpagefiletoP
#Select the P-drive
$drive = Get-WmiObject -Class win32_volume -Filter "DriveLetter = 'P:'"

New-XylemLogWrite -logfile $logfile -linevalue "Change-DVDDrvLetter"
# Change-DVDDrvLetter script
Change-DVDDrvLetter -logfile $logfile

try #to install notepad++
{
    Start-Process -FilePath "D:\temp\tools\npp.7.9.1.Installer.x64.exe" -ArgumentList '/S' -passthru -Wait -NoNewWindow
    New-XylemLogWrite -logfile $logfile -linevalue "Notepad++ Installed"
}
catch
{
    New-XylemLogWrite -logfile $logfile -linevalue "Failed to install notepad++"
    write-host "Failed to install npp"
}
Start-Sleep -Seconds 30

try #BCompare
{
Start-Process -FilePath "D:\temp\tools\BCompare-4.2.10.23938.exe" -ArgumentList '/Silent' #-passthru -Wait -NoNewWindow
New-XylemLogWrite -logfile $logfile -linevalue "BCompare installed"
}
catch
{
New-XylemLogWrite -logfile $logfile -linevalue "BCompared failed to install"
write-host "Failed to install bcompare"
}

Start-Sleep -Seconds 30
try #web platform installer
{
    Start-Process -FilePath "D:\temp\tools\WebPlatformInstaller_x64_en-US.msi" -ArgumentList '/quiet' #-passthru -Wait -NoNewWindow
    New-XylemLogWrite -logfile $logfile -linevalue "Webplatform installed"
}
catch
{
    New-XylemLogWrite -logfile $logfile -linevalue "Webplatform failed to install"
    write-host "Failed to install webplatform"
}

Start-Sleep -Seconds 30
try #url rewrite
{
    Start-Process -FilePath "D:\temp\tools\rewrite_amd64_en-US.msi" -ArgumentList '/quiet'
    #& msiexec /a `"D:\temp\tools\rewrite_amd64_en-US.msi`" /?
    New-XylemLogWrite -logfile $logfile -linevalue "rewrite installed"
}
catch
{
    New-XylemLogWrite -logfile $logfile -linevalue "urlrewrite failed to install"
    write-host "Failed to install urlrewrite"
}

Start-Sleep -Seconds 30
try #install tree
{
    Start-Process -FilePath "D:\temp\tools\TreeSizeFreeSetup.exe" -argumentlist '/silent'
    New-XylemLogWrite -logfile $logfile -linevalue "treesize installed"
}
catch
{
    New-XylemLogWrite -logfile $logfile -linevalue "treesize failed to install"
    write-host "Failed to install treesize"
}
#Update P-drive label
Start-Sleep -Seconds 30
Set-WmiInstance -input $drive -Arguments @{DriveLetter="P:"; Label="Pagefile"}

#>
##########################################################################
################################ END MAIN ################################
##########################################################################

Set-PageFile -logfile $logfile -DriveLetter "P" -SystemManagedSize
Set-PageFile -logfile $logfile -DriveLetter "C" -None -Reboot
Stop-XylemLogFinish -logfile $logfile