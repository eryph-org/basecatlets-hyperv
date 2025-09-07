# Recipe for repacking existing VMs - cleanup and generalization only
# Skips provisioning tasks like first_boot, updates, ui_tweaks

# Ensure cloudbase-init is installed and reset with eryph configuration
include_recipe 'packer::cloudinit_reset'

# Clean up temporary files, event logs, etc.
include_recipe 'packer::cleanup'

# Defragment the disk for optimal size
include_recipe 'packer::defrag'

# Note: sysprep is handled by prepare_sysprep.ps1 and sysprep.ps1 scripts after Chef