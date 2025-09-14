#!/bin/bash -eux

# Cloud-init configuration for RHEL-compatible distributions
# Configures cloud-init for both NoCloud (eryph) and Azure datasources

echo "Configuring cloud-init..."

# Ensure cloud-init packages are installed
if command -v dnf >/dev/null 2>&1; then
    dnf install -y cloud-init cloud-utils-growpart
else
    yum install -y cloud-init cloud-utils-growpart
fi

# Main cloud-init configuration for RHEL-compatible distributions
cat > /etc/cloud/cloud.cfg << 'EOF'
# Cloud configuration for RHEL-compatible distributions

# A set of users which may be applied and/or used by various modules
# when a 'default' entry is found it will reference the 'default_user'
users:
   - default

# If this is set, 'root' will not be able to ssh in
disable_root: true

# This will cause the set+update hostname module to not operate (if true)
preserve_hostname: false

# Datasource configuration for dual support (NoCloud + Azure)
datasource_list: [ NoCloud, Azure ]

# The modules that run in the 'init' stage
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

# The modules that run in the 'config' stage
cloud_config_modules:
 - locale
 - set-passwords
 - yum-add-repo
 - ntp
 - timezone
 - disable-ec2-metadata
 - runcmd

# The modules that run in the 'final' stage
cloud_final_modules:
 - package-update-upgrade-install
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

# System and/or distro specific settings
system_info:
   # This will affect which distro class gets used
   distro: rhel
   # Default user name + that default users groups (if added/used)
   default_user:
     name: admin
     lock_passwd: True
     gecos: Admin
     groups: [wheel, adm]
     sudo: ["ALL=(ALL) NOPASSWD:ALL"]
     shell: /bin/bash
   # Other config here will be given to the distro class and/or path classes
   paths:
      cloud_dir: /var/lib/cloud/
      run_dir: /run/cloud-init/
   ssh_svcname: sshd
   package_mirrors:
     - arches: [x86_64]
       failsafe:
         primary: http://mirror.centos.org/centos/$releasever/os/$basearch/
         security: http://mirror.centos.org/centos/$releasever/updates/$basearch/
EOF

# Configure cloud-init for dual datasource support (NoCloud + Azure)
mkdir -p /etc/cloud/cloud.cfg.d

cat > /etc/cloud/cloud.cfg.d/01-datasource.cfg << 'EOF'
# Datasource configuration for eryph (NoCloud) and Azure compatibility
datasource_list: [ NoCloud, Azure ]
datasource:
  NoCloud:
    # Allow NoCloud to use network if needed
    seedfrom: /var/lib/cloud/seed/nocloud-net/
  Azure:
    apply_network_config: False
    set_hostname: True
EOF

# Configure Hyper-V integration for logging
cat > /etc/cloud/cloud.cfg.d/10-azure-kvp.cfg << 'EOF'
reporting:
  logging:
    type: log
  telemetry:
    type: hyperv
EOF

# Disable network configuration to avoid conflicts with NetworkManager
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg << 'EOF'
network: {config: disabled}
EOF

# Configure cloud-init logging
cat > /etc/cloud/cloud.cfg.d/05-logging.cfg << 'EOF'
# Logging configuration
output: {all: '| tee -a /var/log/cloud-init-output.log'}
EOF

# Enable all cloud-init services
systemctl enable cloud-init-local.service
systemctl enable cloud-init.service
systemctl enable cloud-config.service
systemctl enable cloud-final.service

# Configure cloud-init to run on first boot
rm -f /etc/cloud/cloud-init.disabled

# Set up cloud-init directories
mkdir -p /var/lib/cloud/seed/nocloud-net
mkdir -p /var/lib/cloud/instance
mkdir -p /var/lib/cloud/data

# Configure proper permissions
chown -R root:root /etc/cloud
chmod -R 644 /etc/cloud/cloud.cfg*
chmod 755 /etc/cloud/cloud.cfg.d

# Configure rsyslog for cloud-init
cat > /etc/rsyslog.d/21-cloudinit.conf << 'EOF'
# Cloud-init logging
:programname, isequal, "cloud-init" /var/log/cloud-init.log
& stop
EOF

# Configure logrotate for cloud-init
cat > /etc/logrotate.d/cloud-init << 'EOF'
/var/log/cloud-init.log
/var/log/cloud-init-output.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF

# Clean up any existing cloud-init state (for template preparation)
cloud-init clean --logs || true

echo "Cloud-init configuration completed successfully"