#!/bin/bash
set -euo pipefail

echo "=== Configuring cloud-init for eryph ==="

# Create cloud-init configuration directory
mkdir -p /etc/cloud/cloud.cfg.d

# Configure datasource priority for eryph (NoCloud first, then Azure fallback)
cat > /etc/cloud/cloud.cfg.d/91-nocloud_azure_datasource.cfg << 'EOF'
datasource_list: [ NoCloud, Azure, None ]
datasource:
  NoCloud:
    # Enable NoCloud datasource for eryph fodder system
    seedfrom: /var/lib/cloud/seed/nocloud/
  Azure:
    # Azure fallback configuration
    apply_network_config: false
    data_dir: /var/lib/waagent
    set_hostname: true
EOF

# Configure cloud-init to handle Hyper-V environments
cat > /etc/cloud/cloud.cfg.d/10-hyperv.cfg << 'EOF'
# Hyper-V specific configuration for eryph
datasource:
  Azure:
    apply_network_config: true
    dhclient_lease_file: /var/lib/dhcp/dhclient.eth0.leases

# Enable KVP (Key-Value Pair) reporting for Hyper-V
reporting:
  logging:
    type: log
  telemetry:
    type: hyperv
EOF

# Disable cloud-init network configuration to avoid conflicts with NetworkManager
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg << 'EOF'
network: {config: disabled}
EOF

# Configure cloud-init modules for eryph
cat > /etc/cloud/cloud.cfg.d/10-eryph-modules.cfg << 'EOF'
# eryph-specific cloud-init configuration
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca-certs
 - rsyslog
 - users-groups
 - ssh

cloud_config_modules:
 - ssh-import-id
 - locale
 - set-passwords
 - timezone
 - disable-ec2-metadata
 - runcmd
 - yum-add-repo

cloud_final_modules:
 - package-update-upgrade-install
 - write-files-deferred
 - puppet
 - chef
 - mcollective
 - salt-minion
 - rightscale_userdata
 - scripts-vendor
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message
 - power-state-change
EOF

# Create NoCloud seed directory structure for eryph
mkdir -p /var/lib/cloud/seed/nocloud

# Create default meta-data for NoCloud datasource
cat > /var/lib/cloud/seed/nocloud/meta-data << 'EOF'
instance-id: azure-linux-eryph
local-hostname: azure-linux
EOF

# Create systemd preset to auto-enable cloud-init services
# This works in chroot unlike systemctl commands
mkdir -p /usr/lib/systemd/system-preset
cat > /usr/lib/systemd/system-preset/90-cloud-init.preset << 'EOF'
enable cloud-init.service
enable cloud-config.service
enable cloud-final.service
enable cloud-init-local.service
EOF

echo "✓ Cloud-init configured for eryph (NoCloud + Azure datasources)"