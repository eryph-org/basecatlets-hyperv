# Azure VM Agent - install latest from Microsoft evergreen FWLink.
# Services are stopped + disabled immediately; Unattend.xml's azure-detect.ps1
# specialize-pass command re-enables them only when running on Azure.

remote_file "#{Chef::Config[:file_cache_path]}/WindowsAzureVmAgent.msi" do
  source 'https://go.microsoft.com/fwlink/?LinkID=394789'
  action :create
end

windows_package 'Windows Azure VM Agent' do
  source "#{Chef::Config[:file_cache_path]}/WindowsAzureVmAgent.msi"
  installer_type :msi
  options '/quiet /norestart'
  action :install
end

%w(WindowsAzureGuestAgent RdAgent WindowsAzureTelemetryService).each do |svc|
  service svc do
    action [:stop, :disable]
    ignore_failure true
  end
end

# Deploy the specialize-pass Azure detection script invoked by Unattend.xml.
directory 'C:\Windows\Setup\Scripts' do
  recursive true
  action :create
end

cookbook_file 'C:\Windows\Setup\Scripts\azure-detect.ps1' do
  source 'azure-detect.ps1'
  action :create
end

# Provisioning\Enabled=1 tells the Azure Provisioning Agent (delivered via
# ConfigDrive ISO at deploy time) to run pre-OOBE provisioning steps.
registry_key 'HKLM\SOFTWARE\Microsoft\Windows Azure' do
  recursive true
  action :create
end

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