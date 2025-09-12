# Recipe to apply Eryph-specific patches to cloudbase-init
# This recipe can be included by both cloudinit.rb and cloudinit_reset.rb

# Install Git for Windows to get patch.exe
windows_package 'git' do
  source 'https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe'
  installer_type :inno
  options '/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\\reg\\shellhere,assoc,assoc_sh"'
  action :install
end

# Create reporting directory for new module
directory 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Lib\site-packages\cloudbaseinit\reporting' do
  action :create
  recursive true
end

# Copy new reporting module files
cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Lib\site-packages\cloudbaseinit\reporting\__init__.py' do
  source 'cloudbase-patches/reporting/__init__.py'
end

cookbook_file 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Lib\site-packages\cloudbaseinit\reporting\hypervkvp.py' do
  source 'cloudbase-patches/reporting/hypervkvp.py'
end

# Apply patches for eryph KVP reporting functionality
%w[001-add-hyperv-kvp-config.patch 002-integrate-kvp-reporting.patch 003-fix-azure-service.patch 004-fix-ovf-service.patch].each do |patch_file|
  cookbook_file "C:\\Windows\\Temp\\#{patch_file}" do
    source "cloudbase-patches/#{patch_file}"
  end
  
  execute "apply_#{patch_file}" do
    command "\"C:\\Program Files\\Git\\usr\\bin\\patch.exe\" -p1 --batch -i \"C:\\Windows\\Temp\\#{patch_file}\" && echo Applied > \"C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\#{patch_file}.applied\""
    cwd 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Lib\site-packages'
    # Check if patch already applied by looking for status file
    not_if { ::File.exist?("C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\#{patch_file}.applied") }
    ignore_failure false
  end
end