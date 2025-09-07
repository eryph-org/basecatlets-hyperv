# Recipe to ensure cloudbase-init is installed and reset for repacking
# This handles both fresh installs and resets of existing installations

# Check if cloudbase-init is installed, install if missing
powershell_script 'ensure_cloudbase_init' do
  code <<-EOH
    $cloudbaseInstalled = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Cloudbase-Init*" }
    
    if (-not $cloudbaseInstalled) {
      Write-Host "Cloudbase-Init not found, installing..."
      $url = 'https://www.cloudbase.it/downloads/CloudbaseInitSetup_x64.msi'
      $output = "$env:TEMP\\CloudbaseInitSetup_x64.msi"
      Invoke-WebRequest -Uri $url -OutFile $output
      Start-Process msiexec.exe -ArgumentList '/i', $output, '/quiet', '/norestart' -Wait
      Write-Host "Cloudbase-Init installed"
    } else {
      Write-Host "Cloudbase-Init already installed: $($cloudbaseInstalled.Name)"
    }
  EOH
end

# Stop cloudbase-init service if running
service 'cloudbase-init' do
  action :stop
  ignore_failure true
end

# Clean existing cloudbase-init state and logs
powershell_script 'clean_cloudbase_state' do
  code <<-EOH
    # Remove instance data
    Remove-Item "C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\log\\*" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\LocalScripts\\*" -Force -ErrorAction SilentlyContinue
    
    # Clear any existing cloud-init semaphores
    Remove-Item "C:\\Windows\\System32\\config\\systemprofile\\.cloudbase-init" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Remove registry entries that mark first boot as completed
    Remove-ItemProperty -Path "HKLM:\\SOFTWARE\\Cloudbase Solutions\\Cloudbase-Init" -Name "MetadataFound" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\\SOFTWARE\\Cloudbase Solutions\\Cloudbase-Init" -Name "PluginsExecuted" -ErrorAction SilentlyContinue
    
    Write-Host "Cloudbase-init state cleaned"
  EOH
end

# Deploy eryph-specific configuration files
cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf' do
  source 'cloudbase-init.conf'
  action :create
end

cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init-unattend.conf' do
  source 'cloudbase-init-unattend.conf'
  action :create
end

cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml' do
  source 'Unattend.xml'
  action :create
end

# Ensure the service is set to automatic start
windows_service 'cloudbase-init' do
  action [:enable]
  startup_type :automatic
  ignore_failure true
end

# Reset cloudbase-init to prepare for next boot
powershell_script 'prepare_cloudbase_for_sysprep' do
  code <<-EOH
    # Set cloudbase-init to run on next boot
    Set-ItemProperty -Path "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\cloudbase-init" -Name "DelayedAutostart" -Value 1 -ErrorAction SilentlyContinue
    
    Write-Host "Cloudbase-init prepared for next boot after sysprep"
  EOH
end