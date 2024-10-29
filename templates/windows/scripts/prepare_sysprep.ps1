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

# prevent appx issue: https://learn.microsoft.com/de-de/troubleshoot/windows-client/deployment/sysprep-fails-remove-or-update-store-apps
Write-Host "Removing appx packages for current user"
$packages = Get-AppxPackage | Where-Object PublisherId -eq 8wekyb3d8bbwe
$packages | Remove-AppxPackage -ErrorAction SilentlyContinue | Out-Null
# is this needed? It's in the microsoft article, but it seems to work without it
#$packages | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageFullName -ErrorAction SilentlyContinue | Out-Null }

Write-Host "Optimizing Drive"
Optimize-Volume -DriveLetter C
