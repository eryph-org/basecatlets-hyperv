
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Write-Host
    Exit 1
}

Start-Transcript -Path C:\Windows\Temp\sysprep.log -Append


Write-Host "Cleaning Temp Files..."
try {
  Takeown /d Y /R /f "C:\Windows\Temp\*"
  Icacls "C:\Windows\Temp\*" /GRANT:r administrators:F /T /c /q  2>&1
  Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

Write-Host "CHECKPOINT_01 Preparing sysprep"


#Takeown /F "C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml"
#Icacls "C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml" /GRANT:r administrators:F /T /c /q  2>&1
#$generalizeContent = Get-Content C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml

# patch generalize.xml for error with VAN registry key in Windows Server 2016
#$generalizeContent = $generalizeContent.Replace('HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\VAN\{7724F5B4-9A4A-4a93-AD09-B06F7AB31035}', 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\VAN\{7724F5B4-9A4A-4a93-AD09-B06F7AB31035}')
#$generalizeContent | Set-Content -Path C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml
#icacls "C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml" /setowner "NT Service\TrustedInstaller"

Write-Host "Starting sysprep"

if(Test-Path "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml")
{
    &c:\windows\system32\sysprep\sysprep.exe /oobe /generalize /quit /mode:vm /quiet /unattend:"C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"
}
else {
    &c:\windows\system32\sysprep\sysprep.exe /oobe /generalize /quit /mode:vm /quiet
}

$sysprep_succeded = Test-Path c:\Windows\System32\Sysprep\Sysprep_succeeded.tag

$timeLeft = 900
$waits = 0
while($sysprep_succeded -ne $true){
    
    Write-Host "Waiting for sysprep... ($timeLeft seconds left)"
    $waits++
    Start-Sleep -Seconds 10
    $timeLeft-=10
    $sysprep_succeded = Test-Path c:\Windows\System32\Sysprep\Sysprep_succeeded.tag
    if($waits -ge 90){
        break
    }
}

if($sysprep_succeded -ne $true){

    Write-Host "Sysprep error log content:"
    Get-Content "c:\Windows\System32\Sysprep\Panther\setuperr.log" -ErrorAction Continue

    Write-Host "Sysprep log content:"
    Get-Content "c:\Windows\System32\Sysprep\Panther\setupact.log" -ErrorAction Continue
    
    Write-Error "Sysprep failed" -ErrorAction Stop
    return -1
 }

 Write-Host "CHECKPOINT_02: Sysprep completed"

 ## these changes are applied after sysprep:
## -----------------------------------------------

# disable network discovery
New-Item -Path "HKLM:\System\CurrentControlSet\Control\Network\NewNetworkWindowOff\" | Out-Null


# remove page file - disabled for now as there is currently no automatic re-enable on first boot

#$privileges = Get-WmiObject -Class Win32_computersystem -EnableAllPrivileges
#$privileges.AutomaticManagedPagefile = $false
#$privileges.Put()

#$pagefile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='c:\\pagefile.sys'"
#$pagefile.Delete()

Write-Host "Wiping empty space on disk..."

$FilePath="c:\zero.tmp"
$Volume = Get-WmiObject win32_logicaldisk -filter "DeviceID='C:'"
$ArraySize= 64kb
$SpaceToLeave= $Volume.Size * 0.05
$FileSize= $Volume.FreeSpace - $SpacetoLeave
$ZeroArray= new-object byte[]($ArraySize)

$Stream= [io.File]::OpenWrite($FilePath)
try {
   $CurFileSize = 0
    while($CurFileSize -lt $FileSize) {
        $Stream.Write($ZeroArray,0, $ZeroArray.Length)
        $CurFileSize +=$ZeroArray.Length
    }
}
finally {
    if($Stream) {
        $Stream.Close()
    }
}

Remove-Item $FilePath
Write-Host "CHECKPOINT_03: Cleanup completed"

Write-Host "Randomize Administrator password and disable account"

$currentVersionKey = Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion'
$build = [int]$currentVersionKey.CurrentBuildNumber

Add-Type -AssemblyName System.Web
$adminPasswordPlain = [System.Web.Security.Membership]::GeneratePassword(30,4)

if($build -eq 10240) {
    # Set the administrator password using 'net user'
    $adminUsername = "Administrator"
    net user $adminUsername $adminPasswordPlain

    # Disable the administrator account using WMI
    $adminAccount = Get-WmiObject -Class Win32_UserAccount -Filter "Name='$adminUsername' AND LocalAccount=True"
    if ($adminAccount) {
        $adminAccount.Disabled = $true
        $adminAccount.Put()
    } else {
        Write-Error "Administrator account not found."
    }

} else{

    $adminPassword = ConvertTo-SecureString $adminPasswordPlain -AsPlainText -Force
    $adminAccount = Get-LocalUser Administrator
    $adminAccount | Set-LocalUser -Password $adminPassword
    $adminAccount | Disable-LocalUser
}

Write-Host "Image building completed. Next step will disable packer user account and shutdown the machine"


if($build -eq 10240) {

    $packerAccount = Get-WmiObject -Class Win32_UserAccount -Filter "Name='packer' AND LocalAccount=True"
    if ($packerAccount) {
        $packerAccount.Disabled = $true
        $packerAccount.Put()
    } else {
        Write-Error "Packer account not found."
    }

}
else{
    $packerAccount = Get-LocalUser packer -ErrorAction Continue
    $packerAccount | Disable-LocalUser -ErrorAction Continue
}

Write-Host "CHECKPOINT_04: Shutdown"
Stop-Computer -Force -ErrorAction Continue

