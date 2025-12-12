#Requires -RunAsAdministrator
#Explorance Inc. - Script to install the BIM Daemon

param (    
    #enter y if this is a brand new installation. else enter n if this is to upgrade the daemon version
    [string]$deploytype = $( Read-Host "Is New Installation? (y/n)" )
)

$keyvaultname = "" #the key vault name
$daemonlogpath = "C:\temp\bim-daemon-logs" #the path where the bim daemon will save its log

$servicepath = "$Env:Programfiles\ExploranceBIMDaemon" #where the bim daemon will be installed as a windows service
$zipfolder = "C:\temp" #the folder where the bim daemon will save the downloaded daemon zip file
$zippath = "$zipfolder\bimdaemon-app.zip"
$url = "https://stbimdtr01onprem01.blob.core.windows.net/dev/daemon/latest/bimdaemon-app.zip" # the bim daemon zip file
$bimdaemon = "bimdaemon"

if ($keyvaultname -eq "")
{
    Write-Host "The key vault name has not been entered in the script"
    exit    
}

if (-Not(Test-Path $servicepath))
{
    Write-Host "The path $servicepath does not exist. The path will be created."
    New-Item -ItemType "Directory" -Path $servicepath
}

if (-Not(Test-Path $zipfolder))
{
    Write-Host "The path $zipfolder does not exist. The path will be created." 
    New-Item -ItemType "Directory" -Path $zipfolder
}

if (-Not(Test-Path $daemonlogpath))
{
    Write-Host "The path $daemonlogpath does not exist. The path will be created."
    New-Item -ItemType "Directory" -Path $daemonlogpath
}

#If new installation
if ($deploytype -eq 'y')
{
    #Check if service already exists
    if (Get-Service -name $bimdaemon -ErrorAction SilentlyContinue)
    {
        Write-Host "The windows service '$bimdaemon' already exists. Please delete this service before continuing with a new installation."
        exit
    }
}

#Invoke-Request overwrites by default
Write-Host 'Downloading daemon zip file'
Invoke-WebRequest -Uri $url -OutFile $zippath

#If New installation
if ($deploytype -eq 'y')
{
    Write-Host "Starting new installation"
    Write-Host "Removing all files in $servicepath"
    Get-ChildItem -Path $servicepath -File -Recurse |
    Remove-Item

    Write-Host "Unzipping daemon package to $servicepath"
    Expand-Archive $zippath -DestinationPath $servicepath    

    $file = $servicepath + "\Explorance.BimDaemon.WorkerService.dll"
    $vip = (Get-Item $file).VersionInfo.ProductVersion    

    Write-Host 'Create windows service'
    $params = @{
      Name = $bimdaemon
      BinaryPathName = $servicepath + "\Explorance.BimDaemon.WorkerService.exe"
      DisplayName = "Explorance BIM Daemon Service $vip"
      StartupType = "Automatic"
      Description = "Explorance BIM Daemon service."
      DependsOn = "himds"
    }
    New-Service @params
}
else {
    Write-Host "Starting upgrade"
    Write-Host "Stopping windows service '$bimdaemon'"
    Stop-Service -Name $bimdaemon

    Start-Sleep -Seconds 10
        
    Write-Host 'Removing files except *.daemon.json (appsettings.json will be overwritten)'
    Get-ChildItem -Path $servicepath -File -Recurse |
    Where-Object { -not $_.Name.EndsWith(".daemon.json") } |
    Remove-Item

    Write-Host 'Unzipping file'
    Expand-Archive $zippath -DestinationPath $servicepath
        
    Start-Sleep -Seconds 5

    Write-Host 'Update service display name'
    $file = $servicepath + "\Explorance.BimDaemon.WorkerService.dll"
    $vip = (Get-Item $file).VersionInfo.ProductVersion    
    $newname = "Explorance BIM Daemon Service " + $vip

    Set-Service -Name $bimdaemon -DisplayName $newname
}

# add the key vault name and daemon log path in the daemon appsettings.json

Write-Host 'Reading appsettings.json'
$jsonfile = "$servicepath\appsettings.json"
$json = Get-Content -Path $jsonfile -Raw | ConvertFrom-Json

if ($json)
{
    Write-Host 'appsettings.json is read'
}
else {
    Write-Host 'appsettings.json could not be read'
}

$json.KeyVaultName = $keyvaultname
$json.DaemonSettings.LogFolderPath = $daemonlogpath
$json.DaemonSettings.UseRegistration = $false

Write-Host 'Writing to appsettings.json'
$json | ConvertTo-Json | Out-File $jsonfile

Write-Host 'Start windows service'
Start-Service -Name $bimdaemon