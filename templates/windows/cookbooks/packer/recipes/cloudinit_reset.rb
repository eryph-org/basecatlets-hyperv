# Recipe to reset cloudbase-init for repacking
# Cleans state and ensures proper installation with eryph patches

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

# Ensure cloudbase-init is properly installed with eryph patches and configuration
include_recipe 'packer::cloudinit'

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