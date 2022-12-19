Write-Host "Uninstalling Chef..."
$app = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -match "Chef"
}
$app.Uninstall()

Write-Host "Removing leftover Chef files..."
Remove-Item "C:\Opscode\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Chef\" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Cleaning Temp Files..."
try {
  Takeown /d Y /R /f "C:\Windows\Temp\*"
  Icacls "C:\Windows\Temp\*" /GRANT:r administrators:F /T /c /q  2>&1
  Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

Write-Host "Optimizing Drive"
Optimize-Volume -DriveLetter C

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

if(Test-Path "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml")
{
    &c:\windows\system32\sysprep\sysprep.exe /oobe /generalize /quit /mode:vm /quiet /unattend:"C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"
}
else {
    &c:\windows\system32\sysprep\sysprep.exe /oobe /generalize /quit /mode:vm /quiet
}


# wait for sysprep
Start-Sleep -Seconds 60

## these changes are applied after sysprep:
## -----------------------------------------------

# generalize may reset Administrator password, so do this at end
# set a random password and disable administrator user
Add-Type -AssemblyName System.Web
$adminPasswordPlain = [System.Web.Security.Membership]::GeneratePassword(30,4)
$adminPassword = ConvertTo-SecureString $adminPasswordPlain -AsPlainText -Force
$adminAccount = Get-LocalUser Administrator
$adminAccount | Set-LocalUser -Password $adminPassword
$adminAccount | Disable-LocalUser

# disable autologon for administrator
set-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0

# disable network discovery
New-Item -Path "HKLM:\System\CurrentControlSet\Control\Network\NewNetworkWindowOff\"


Stop-Computer -Force

