# Azure VM Agent installation - Azure-specific only
# This ensures Windows VMs are always Azure-compatible

# Download the Azure VM Agent MSI
remote_file "#{Chef::Config[:file_cache_path]}/WindowsAzureVmAgent.msi" do
  source 'https://github.com/Azure/WindowsVMAgent/releases/download/2.7.41491.1172AMD64%26ARM64/WindowsAzureVmAgent.amd64_2.7.41491.1172_2507161172.fre.msi'
  checksum 'bf14455dcc754164db546d7045751adb8f4b952371ea59004949f8a13a4146df'
  action :create_if_missing
end

# Install Azure VM Agent
windows_package 'Windows Azure VM Agent' do
  source "#{Chef::Config[:file_cache_path]}/WindowsAzureVmAgent.msi"
  installer_type :msi
  options '/quiet /norestart'
  action :install
end


# Set registry values for Azure VM Agent
registry_key 'HKLM\SOFTWARE\Microsoft\Windows Azure' do
  recursive true
  action :create
end

# Configure Azure VM provisioning settings
registry_key 'HKLM\SOFTWARE\Microsoft\Windows Azure\Provisioning' do
  values [
    {
      name: 'Enabled',
      type: :dword,
      data: 1
    }
  ]
  recursive true
  action :create
end