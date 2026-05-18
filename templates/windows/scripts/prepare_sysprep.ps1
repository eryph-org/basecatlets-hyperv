Write-Host "Uninstalling Chef/Cinc..."
# Try to uninstall both Chef and Cinc using faster registry-based approach
$apps = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object {
    $_.DisplayName -match "(Chef|Cinc)"
}

foreach($app in $apps) {
    if($app.UninstallString) {
        Write-Host "Uninstalling: $($app.DisplayName)"
        try {
            $uninstallString = $app.UninstallString
            if($uninstallString -match "msiexec") {
                # MSI uninstall
                $guid = $uninstallString -replace ".*\{(.*)\}.*", '{$1}'
                Start-Process "msiexec.exe" -ArgumentList "/x $guid /quiet /norestart" -Wait -NoNewWindow
            } else {
                # Other installer
                Start-Process $uninstallString -ArgumentList "/S" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "Failed to uninstall $($app.DisplayName): $_"
        }
    }
}

Write-Host "Removing leftover Chef/Cinc files..."
Remove-Item "C:\Opscode\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Chef\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\cinc\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\packer\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\packages\" -Recurse -Force -ErrorAction SilentlyContinue

# Note: C:\Windows\Temp\packer* files are left in place; deleting them here
# breaks packer's elevated-shell wrapper which still needs its env-vars file.
# sysprep.ps1 (run as shutdown_command) wipes C:\Windows\Temp\* at the right time.

# disable autologon for packer user
set-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0

Write-Host "Removing appx packages for current user"

# prevent appx issue: https://learn.microsoft.com/de-de/troubleshoot/windows-client/deployment/sysprep-fails-remove-or-update-store-apps
Get-AppxPackage | Remove-AppxPackage -ErrorAction SilentlyContinue | Out-Null

Write-Host "Optimizing Drive"
Optimize-Volume -DriveLetter C



