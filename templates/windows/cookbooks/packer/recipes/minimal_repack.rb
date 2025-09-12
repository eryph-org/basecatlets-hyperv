# Minimal recipe for repacking existing VMs - essential cleanup only
# Skips defragmentation and other time-consuming operations

# Apply essential cloud optimizations to all repacked VMs
include_recipe 'packer::configure_power'

# Ensure Azure VM Agent is installed for universal compatibility
include_recipe 'packer::azure'

# Ensure cloudbase-init is installed and reset with eryph configuration
# This is essential for eryph catlets to work properly
include_recipe 'packer::cloudinit_reset'

# Clean up temporary files, event logs, etc.
include_recipe 'packer::cleanup'

# Skip defrag for faster processing

# Note: sysprep is handled by prepare_sysprep.ps1 and sysprep.ps1 scripts after Chef