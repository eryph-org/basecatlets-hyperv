
include_recipe 'packer::disable_restore'
include_recipe 'packer::ui_tweaks'

# OneDrive takes up 150 megs and isn't needed for testing
windows_package 'Microsoft OneDrive' do
  action :remove
end

# Skype takes up 26 megs
windows_package 'Skype' do
  action :remove
end

windows_feature 'Windows-Defender' do
  action :remove
end
