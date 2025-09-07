# Minimal recipe for repacking existing VMs - essential cleanup only
# Skips defragmentation and other time-consuming operations

# Ensure cloudbase-init is installed and reset with eryph configuration
# This is essential for eryph catlets to work properly
include_recipe 'packer::cloudinit_reset'

# Clean up temporary files, event logs, etc.
include_recipe 'packer::cleanup'

# Skip defrag for faster processing

# Note: sysprep is handled by prepare_sysprep.ps1 and sysprep.ps1 scripts after Chef