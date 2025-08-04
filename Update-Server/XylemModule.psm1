# Please place me in C:\Windows\system32\WindowsPowerShell\v1.0\Modules\XylemModule directory with Manifest.
# Created 11/12/2020 EMS Original

################################################################
######################## LOGGING FUNCTIONS #####################
################################################################
<#
 .Synopsis
  Creates the top line for log entries, which contains date and time stamp

 .Description
  Creates the logfile and writes the time of creation for log information handling

 .Parameter Logfile
  Specify where the logfile should be created/written to

 .Example
   # Create a logfile and write the first entry to a test directory
   Start-XylemLogCreate -Logfile C:\Test\Logfile.txt

#>
function Start-XylemLogCreate
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$logfile
    )

    if (!(Test-Path -path $logFile))
    {
        New-item -ItemType file -Path $logFile -Force
    }
    Add-Content -Path $logfile -Value "***************************************************************************************************"
    Add-Content -Path $logfile -Value "Started processing at [$([DateTime]::Now)]."
    Add-Content -Path $logfile -Value "***************************************************************************************************"
}
<#
 .Synopsis
  Creates a new line for log entries

 .Description
  This should be used after Start-XylemLogCreate

 .Parameter Logfile
  Specify where the logfile is located
   
 .Parameter linevalue
  Specify what the log entry will contain

 .Example
   # Create a logfile and write the first entry to a test directory
   New-XylemLogWrite -Logfile C:\Test\Logfile.txt -linevalue "This is a log entry"

#>
function New-XylemLogWrite
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$logfile,
        [Parameter(Mandatory=$true)][string]$linevalue
    )
    Add-Content -Path $Logfile -Value $LineValue
}
<#
 .Synopsis
  Creates a new error line for log entries

 .Description
  This should be used after Start-XylemLogCreate

 .Parameter Logfile
  Specify where the logfile is located
   
 .Parameter errorDesc
  Specify what the error log entry will contain

 .Example
   # Create a logfile and write the first entry to a test directory
   New-XylemLogError -Logfile C:\Test\Logfile.txt -errorDesc "This is a log error entry"

#>
function New-XylemLogError
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$logfile,
        [Parameter(Mandatory=$true)][string]$errorDesc
    )
    Add-Content -Path $Logfile -Value "Error: An error has occurred [$errorDesc]."
}
<#
 .Synopsis
  Creates a new line in the logfile, to close it out

 .Description
  This should be used after Start-XylemLogCreate, and will be the last function used in the log file

 .Parameter Logfile
  Specify where the logfile is

 .Example
   # Create a logfile and write the first entry to a test directory
   Stop-XylemLogFinish -Logfile C:\Test\Logfile.txt

#>
function Stop-XylemLogFinish
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$logfile
    )
    Add-Content -Path $logfile -Value "***************************************************************************************************"
    Add-Content -Path $logfile -Value "Finished processing at [$([DateTime]::Now)]."
    Add-Content -Path $logfile -Value "*****************************************************************************************"
}

function New-XylemLogEmail
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$logfile,
        [Parameter(Mandatory=$true)][string]$emailTo,
        [Parameter(Mandatory=$true)][string]$emailFrom,
        [Parameter(Mandatory=$true)][string]$emailSubject
    )
      $sBody = (Get-Content $Logfile | out-string)
      
      #Create SMTP object and send email
      $sSmtpServer = "1.1.1.1" #whatever the smtp server address is
      $oSmtp = new-object Net.Mail.SmtpClient($sSmtpServer)
      $oSmtp.Send($EmailFrom, $EmailTo, $EmailSubject, $sBody)
      Exit 0

}

################################################################
##################### END LOGGING FUNCTIONS ####################
################################################################


################################################################
######################### MAIN FUNCTIONS #######################
################################################################
function New-XylemDirectory #create directory
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$directorypath,
        [Parameter(Mandatory=$false)][string]$logfile
    )
    if (!(Test-Path -path $directorypath))
    {
        New-Item $directorypath -ItemType directory
        if ($logfile)
        {
            New-XylemLogWrite -logfile -linevalue "Created $directorypath"
        }
    }
}
function New-XylemWebsite #website
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$websiteName,
        [Parameter(Mandatory=$true)][string]$applicationPool,
        [Parameter(Mandatory=$true)][string]$logfile,
        [Parameter(Mandatory=$true)][string]$port,
        [Parameter(Mandatory=$true)][string]$physicalpath
    )
    if ( (!$logfile) -or (!$applicationPool) -or (!$websiteName))
    {
        New-XylemLogWrite -logfile $logfile -linevalue "One of the variables is not being used"
    }

    if (!(test-path "IIS:\Sites\$websiteName"))
    {
        try
        {
            New-Website -Name $websiteName -Port $port -HostHeader $websiteName -PhysicalPath $physicalpath -ApplicationPool $applicationPool -Force
            New-XylemLogWrite -logfile $logfile -linevalue "Web Site Creation for $websiteName was successful"
        }
        catch
        {
            New-XylemLogError -logfile $logfile -errordesc "Website Creation Failed"
        }
    }
    else {New-XylemLogWrite -logfile $logfile -linevalue "Website $websiteName exists, continuing script"}
}
function New-XylemWebAppPool #app pool
{
    Param
(
    [Parameter(Mandatory=$true)][string]$applicationPool,
    [Parameter(Mandatory=$true)][string]$logfile,
    [Parameter(Mandatory=$false)][string]$username,
    [Parameter(Mandatory=$false)][string]$password
)
    $GetAppPoolList = Get-Item -Path "IIS:\AppPools" #stores application pool list
    if (!($GetAppPoolList.Children.Keys.Contains($applicationPool))) #checks to make sure it doesn't already exist.
    {
        New-XylemLogWrite -logfile $logfile -linevalue "IIS:\AppPools\$applicationPool location does not exist, creating location"
        New-WebAppPool -Name $applicationPool -Force
        $AppPoolProperties = Get-Item("IIS:\AppPools\$applicationPool")
        $AppPoolProperties.managedRuntimeVersion = "v4.0"
        if (!($username) -and !($password))   #set for no password provided
        {
            $AppPoolProperties.processModel.identityType = 2
            $AppPoolProperties | Set-Item
        }
        if ($username -and $password) #set for password provided
        {
            $AppPoolProperties.processModel.username = $username
            $AppPoolProperties.processModel.password = $password
            $AppPoolProperties.processModel.identityType = 3
            $AppPoolProperties | Set-Item
        }
        if (($username -and !$password) -or (!$username -and $password))
        {
            Write-Host "Please both sure either BOTH password and username are filled out or NEITHER"
        }
    }
    else {New-XylemLogWrite -logfile $logfile -linevalue "AppPool $applicationPool exists, continuing script"}
}
function New-XylemWebApplication #web app
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$webAppName,
        [Parameter(Mandatory=$true)][string]$webAppSite,
        [Parameter(Mandatory=$true)][string]$physicalpath,
        [Parameter(Mandatory=$true)][string]$appPool,
        [Parameter(Mandatory=$true)][string]$logfile
    )
    
    if (!(Get-WebApplication -Name $webAppName -site $webAppSite)) #make sure it doesn't already exist
    {
        New-WebApplication -site $webAppSite -Name $webAppName -PhysicalPath $physicalpath -ApplicationPool $appPool -Force
        New-XylemLogWrite -logfile $logfile -linevalue "Created Web Application for $webAppName with physical path: $physicalpath and appPool:$appPool"
    }
    else {New-XylemLogWrite -logfile $logfile -linevalue "Web Application exists for $webAppName, continuing script"}
}
function New-XylemWebBinding #for SSL
{
        Param
    (
        [Parameter(Mandatory=$true)][string]$bindingname,
        [Parameter(Mandatory=$true)][string]$port,
        [Parameter(Mandatory=$true)][string]$logfile,
        [Parameter(Mandatory=$true)][string]$IP
    )
    try
    {
        New-WebBinding -Name $bindingname -IP IP -Port $port -Protocol https 
        New-XylemLogWrite -logfile $logfile -linevalue "Starting Web Binding for $bindingname with port: $port with https and $IP"
        try
        {
             $cert = dir cert:\localmachine\my | where { $_.subject -like "*$bindingname"} | select -last 1
             $thumb = $cert.thumbprint
             get-item "cert:\LocalMachine\MY\$thumb" | new-item IIS:\SslBindings\0.0.0.0!$port
             New-XylemLogWrite -logfile $logfile -linevalue "Binding cert: $($cert.subject) was successful"
        }
        catch
        {
             New-XylemLogError -logfile $logfile -errordesc "Binding Certificate Failed"
             #exit
        }
    }
    catch
    {
        New-XylemLogWrite -logfile $logfile -linevalue "Binding Failed"
        #exit
    }
}
Function Install-XylemServices
{
    Param
    (
        [Parameter(Mandatory=$true)][string]$service,
        [Parameter(Mandatory=$true)][string]$logfile,
        [Parameter(Mandatory=$true)][string]$servicepathexe,
        [Parameter(Mandatory=$true)][string]$servicedisplayname
    )

    New-XylemLogWrite -logfile $logfile -linevalue "Installing Services"


    if (Get-Service $service -ErrorAction SilentlyContinue)
    {
        New-XylemLogWrite -logfile $logfile -linevalue "Service exists for $service"
    }
    else 
    {
        New-Service -Name $service -BinaryPathName $servicepathexe -StartupType Automatic -DisplayName $servicedisplayname
        New-XylemLogWrite -logfile $logfile -linevalue "Creating Service for $service"
    }
    try
    {
        Start-Service -Name $service -ErrorAction SilentlyContinue
    }
    catch
    {
        New-XylemLogError -logfile $logfile -errordesc "Starting Service $service failed"
    }
    New-XylemLogWrite -logfile $logfile -linevalue "Finished Starting Service $service Successfully"
}
################################################################
##################### END MAIN FUNCTIONS #######################
################################################################