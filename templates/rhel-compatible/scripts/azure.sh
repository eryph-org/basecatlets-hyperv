#!/bin/bash -eux

# Azure Linux Agent configuration for RHEL-compatible distributions
# Configures WALinuxAgent to work with cloud-init for Azure compatibility

echo "Configuring Azure Linux Agent..."

# Ensure WALinuxAgent is installed
if command -v dnf >/dev/null 2>&1; then
    dnf install -y WALinuxAgent
else
    yum install -y WALinuxAgent
fi

# Configure WALinuxAgent to work with cloud-init
cat > /etc/waagent.conf << 'EOF'
# WALinuxAgent configuration for RHEL-compatible distributions
# Modern configuration for 2024+ compatibility with cloud-init

# Provisioning - let cloud-init handle provisioning
Provisioning.Agent=auto
Provisioning.Enabled=n
Provisioning.UseCloudInit=y
Provisioning.AllowResetSysUser=n
Provisioning.RegenerateSshHostKeyPair=n
Provisioning.DeleteRootPassword=n
Provisioning.DecodeCustomData=n
Provisioning.ExecuteCustomData=n
Provisioning.MonitorHostName=n

# Resource disk - disable formatting (leave to cloud-init/user)
ResourceDisk.Format=n
ResourceDisk.EnableSwap=n
ResourceDisk.MountPoint=/mnt/resource
ResourceDisk.MountOptions=None
ResourceDisk.Filesystem=ext4
ResourceDisk.EnableSwapEncryption=n

# Extensions and auto-update
Extensions.Enabled=y
AutoUpdate.Enabled=y

# Logs and HTTP settings
Logs.Verbose=n
OS.AllowHTTP=n
OS.CheckRdmaDriver=n

# Root device timeout
OS.RootDeviceScsiTimeout=300

# Enable CGroup v2 support if available
CGroups.EnforceLimits=n
CGroups.Excluded=

# Network configuration
DetectScvmmEnv=n
EnableRDMA=y

# SSH key generation
Provisioning.SshHostKeyPairType=rsa
EOF

# Enable waagent service
systemctl enable waagent.service

# Note: Cloud-init datasource configuration is handled in kickstart
# Note: Hyper-V KVP logging and network config are handled in kickstart
# This script only configures WALinuxAgent

# Configure cloud-init modules for Azure
cat > /etc/cloud/cloud.cfg.d/05-azure-modules.cfg << 'EOF'
# Azure-specific cloud-init configuration
system_info:
  default_user:
    name: azureuser
    lock_passwd: True
    gecos: Cloud User
    groups: [wheel, adm]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash

# Disable root login
disable_root: true

# Azure VM agent compatibility
write_files: []
runcmd: []
EOF

# Configure udev rules for consistent device naming in Azure
cat > /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules << 'EOF'
# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
# This interface is transparently bonded to the synthetic interface,
# so NetworkManager should just ignore any SRIOV interfaces.
SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"
EOF

# Configure waagent systemd override for better reliability
mkdir -p /etc/systemd/system/waagent.service.d
cat > /etc/systemd/system/waagent.service.d/override.conf << 'EOF'
[Unit]
After=network-online.target cloud-init-local.service
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=5
EOF

# Configure rsyslog for Azure agent logging
cat > /etc/rsyslog.d/99-waagent.conf << 'EOF'
# Azure Linux Agent logging
if $programname contains "waagent" then /var/log/waagent.log
& stop
EOF

# Configure logrotate for waagent logs
cat > /etc/logrotate.d/waagent << 'EOF'
/var/log/waagent.log {
    monthly
    rotate 6
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog adm
}
EOF

# Ensure proper permissions
chmod 644 /etc/waagent.conf
systemctl daemon-reload

echo "Azure Linux Agent configuration completed successfully"