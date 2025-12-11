#Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

<#
.Synopsis
	Installing pre-requisites for running Blue 9 bundle of applications (Blue Core, BlueNext and Blue Landing Page
.DESCRIPTION
	The prerequisites for the Blue 9 applications for Windows OS 2022 server
.EXAMPLE
	powershell.exe Blue9_Bundle_Prerequisites.ps1
#>

function  Enable-ASPNET {

	Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All -NoRestart
    
}


function Install-ASPNETHostingBundle6 {

    $InstallerUrl = "https://download.visualstudio.microsoft.com/download/pr/6127ac20-be25-437d-ab6a-e90415f3d547/f572f0b58361ccff32a961ad4446bb24/dotnet-hosting-6.0.22-win.exe"
    
    $OutFilePath = "$env:TEMP\netinstaller-dotnet-hosting-6.exe"

    try {
        $WebClient = [System.Net.WebClient]::new()
        $WebClient.Downloadfile($InstallerUrl, $OutFilePath)
        $WebClient.Dispose()
    }
    catch {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $OutFilePath 
    }

    try{    & "$OutFilePath" /install /quiet /norestart
    
    
        while ($(Get-Process | Where-Object {$_.Name -like "*netinstaller*"})) {
            Write-Host "Installing .Net Hosting bundle 6.x  ..."
            Start-Sleep -Seconds 5
        }
    
        Write-Host ".Net Hosting bundle 6.x installed" -ForegroundColor Green
    
    }
    catch{

        Write-Host ".Net Hosting bundle 6.x installation failed" -ForegroundColor Red
		Write-Warning $_
    }
	
	# Best-effort cleanup
    Get-Item $OutFilePath -ErrorAction SilentlyContinue|Remove-Item
}

function Install-AspnetRuntime7 {

        $InstallerUrl = "https://download.visualstudio.microsoft.com/download/pr/91644a20-1e21-43c9-8ae0-90e402c1a368/469c198fab110c6c3d822e03509e9aec/dotnet-hosting-7.0.11-win.exe"
    
		$OutFilePath = "$env:TEMP\netinstaller70runtime.exe"

    try {
        $WebClient = [System.Net.WebClient]::new()
        $WebClient.Downloadfile($InstallerUrl, $OutFilePath)
        $WebClient.Dispose()
    }
    catch {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $OutFilePath 
    }

    
       # & "$HOME\Downloads\NDP472-KB4054530-x86-x64-AllOS-ENU.exe" /q
    try{    & "$OutFilePath" /install /quiet /norestart
    
    
        while ($(Get-Process | Where-Object {$_.Name -like "*netinstaller*"})) {
            Write-Host "Installing Asp Net Runtime 7.x  ..."
            Start-Sleep -Seconds 5
        }
    
        Write-Host "Asp Net Runtime 7.x installed" -ForegroundColor Green
    
    }
    catch{

        Write-Host "Asp Net Runtime 7.x installation failed" -ForegroundColor Red
		Write-Warning $_
    }
	
	# Best-effort cleanup
    Get-Item $OutFilePath -ErrorAction SilentlyContinue|Remove-Item
}

function Enable-WCF(){

	Enable-WindowsOptionalFeature -Online -FeatureName "WCF-Services45" -All -NoRestart
	Enable-WindowsOptionalFeature -Online -FeatureName "WCF-HTTP-Activation45" -All -NoRestart
	Enable-WindowsOptionalFeature -Online -FeatureName "WCF-TCP-Activation45" -All -NoRestart
	Enable-WindowsOptionalFeature -Online -FeatureName "WCF-Pipe-Activation45" -All -NoRestart
	Enable-WindowsOptionalFeature -Online -FeatureName "WCF-TCP-PortSharing45" -All -NoRestart

}


function Install-DotNet472Plus {


    $Net472Check = Get-ChildItem "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" | Get-ItemPropertyValue -Name Release | ForEach-Object { $_ -ge 461808 }
    if ($Net472Check) {
        Write-Warning ".Net 4.7.2 (or higher) is already installed! Halting!"
        return
    }

    $InstallerUrl = "https://download.visualstudio.microsoft.com/download/pr/2d6bb6b2-226a-4baa-bdec-798822606ff1/9b7b8746971ed51a1770ae4293618187/ndp48-web.exe"
        
        $OutFilePath = "$env:TEMP\netNDPinstaller.exe"

    try {
        $WebClient = [System.Net.WebClient]::new()
        $WebClient.Downloadfile($InstallerUrl, $OutFilePath)
        $WebClient.Dispose()
    }
    catch {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $OutFilePath 
    }

	try{
		& "$OutFilePath" /q /norestart

		
		while ($(Get-Process | Where-Object {$_.Name -like "*netNDPinstaller*"})) {
			Write-Host "Installing .Net Framework 4.7 or higher ..."
			Start-Sleep -Seconds 5
		}

		Write-Host ".Net Framework 4.7 or higher was installed successfully!" -ForegroundColor Green
	}
	catch{

        Write-Host ".Net Framework 4.7 or higher installation failed" -ForegroundColor Red
		Write-Warning $_
    }
	
	# Best-effort cleanup
    Get-Item $OutFilePath -ErrorAction SilentlyContinue|Remove-Item
}

function Install-ASPNETCoreHostingBundle8 {
    $InstallerUrl = "https://download.visualstudio.microsoft.com/download/pr/4956ec5e-8502-4454-8f28-40239428820f/e7181890eed8dfa11cefbf817c4e86b0/dotnet-hosting-8.0.11-win.exe"
    
    $OutFilePath = "$env:TEMP\aspnetcore-runtime-8.0.8-win-x64.exe"

    try {
        $WebClient = [System.Net.WebClient]::new()
        $WebClient.Downloadfile($InstallerUrl, $OutFilePath)
        $WebClient.Dispose()
    }
    catch {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $OutFilePath 
    }

    try {
        Write-Host "Installing ASP.NET Core Hosting Bundle 8.0.8 ..."
        & "$OutFilePath" /install /quiet /norestart
        
        while ($(Get-Process | Where-Object {$_.Name -like "*aspnetcore-runtime*"})) {
            Write-Host "Installing ASP.NET Core Hosting Bundle 8.0.8 ..."
            Start-Sleep -Seconds 5
        }

        Write-Host "ASP.NET Core Hosting Bundle 8.0.8 installed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "ASP.NET Core Hosting Bundle 8.0.8 installation failed" -ForegroundColor Red
        Write-Warning $_
    }

    # Best-effort cleanup
    Get-Item $OutFilePath -ErrorAction SilentlyContinue | Remove-Item
}

function Install-PowerShell7 {
    $url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi"
    $installerPath = "$env:TEMP\PowerShell-7.4.6-win-x64.msi"
    
    # Check if PowerShell 7 is already installed
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        Write-Host "PowerShell 7 is already installed." -ForegroundColor Green
        return
    }

    Write-Host "PowerShell 7 is not installed. Downloading and installing..." -ForegroundColor Yellow

    # Download the PowerShell 7 installer
    try {
        Write-Host "Downloading PowerShell 7 installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $installerPath

        # Install PowerShell 7 using the MSI installer
        Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
        Start-Process msiexec.exe -ArgumentList "/i", $installerPath, "/quiet", "/norestart" -Wait

        Write-Host "PowerShell 7 installation completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to download or install PowerShell 7. Error: $_" -ForegroundColor Red
    }
    finally {
        # Clean up the installer file
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force
            Write-Host "Installer file cleaned up." -ForegroundColor Green
        }
    }
} 

function Install-DotNet8 {
    $version = "8.0.21"
    $url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$version/dotnet-hosting-$version-win.exe"
    $installerPath = "$env:TEMP\dotnet-hosting-$version-win.exe"

    # Download the installer
    Invoke-WebRequest -Uri $url -OutFile $installerPath

    # Install silently
    # /quiet is silent, /norestart prevents automatic reboot
    $arguments = "/quiet /norestart"

    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Host "Installation succeeded"
    } else {
        Write-Error "Installation failed with exit code $($process.ExitCode)"
}    
}

function Enable-TLS-1-2 {
    If (-Not (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'))
    {
        New-Item 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null

    If (-Not (Test-Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'))
    {
        New-Item 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name 'SystemDefaultTlsVersions' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -PropertyType 'DWord' -Force | Out-Null

    If (-Not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'))
    {
        New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Name 'Enabled' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server' -Name 'DisabledByDefault' -Value '0' -PropertyType 'DWord' -Force | Out-Null

    If (-Not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'))
    {
        New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Name 'Enabled' -Value '1' -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Name 'DisabledByDefault' -Value '0' -PropertyType 'DWord' -Force | Out-Null

    Write-Host 'TLS 1.2 has been enabled. You must restart the Windows Server for the changes to take affect.' -ForegroundColor Cyan
}
 
Enable-WCF
Enable-ASPNET
#Install-ASPNETHostingBundle6
Install-DotNet8
Install-AspnetRuntime7
Install-ASPNETCoreHostingBundle8
Install-DotNet472Plus
Install-WindowsFeature -name Web-WebSockets
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationInit
Install-PowerShell7 
Enable-TLS-1-2