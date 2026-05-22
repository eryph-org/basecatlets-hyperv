# Recipe for repacking existing VMs - cleanup and generalization only
# Skips provisioning tasks like first_boot, updates, ui_tweaks

# Apply cloud optimizations to all repacked VMs
include_recipe 'packer::configure_power'

# Ensure Azure VM Agent is installed for universal compatibility
include_recipe 'packer::azure'

# Clean up temporary files, event logs, etc.
include_recipe 'packer::cleanup'

# Defragment the disk for optimal size
include_recipe 'packer::defrag'

# Note: sysprep is handled by prepare_sysprep.ps1 and sysprep.ps1 scripts after Chef