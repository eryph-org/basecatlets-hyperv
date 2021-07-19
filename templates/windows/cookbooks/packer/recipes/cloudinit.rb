
windows_package 'cloudinit' do
  source 'https://www.cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi'
end

cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf' do
  source 'cloudbase-init.conf'
end

cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init-unattend.conf' do
  source 'cloudbase-init-unattend.conf'
end

cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml' do
  source 'Unattend.xml'
end
