Write-Host "Uninstalling Chef..."
$app = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -match "Chef"
}

if($app){ $app.Uninstall() }

Write-Host "Removing leftover Chef files..."
Remove-Item "C:\Opscode\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Chef\" -Recurse -Force -ErrorAction SilentlyContinue

# disable autologon for packer user
set-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0


Write-Host "Optimizing Drive"
Optimize-Volume -DriveLetter C
