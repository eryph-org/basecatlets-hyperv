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
Logs.Console=n
OS.AllowHTTP=n
OS.CheckRdmaDriver=n

# Root device timeout
OS.RootDeviceScsiTimeout=300

# Enable CGroup v2 support if available
CGroups.EnforceLimits=n
CGroups.Excluded=

# Network configuration
DetectScvmmEnv=n

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

# Gate the agent to Azure-only. Off-Azure (eryph/Hyper-V) cloud-init does all
# provisioning and the agent would otherwise retry the Azure wireserver
# (168.63.129.16) forever. ExecCondition exits the unit silently when the Azure
# DMI chassis asset tag is absent (generic Hyper-V leaves it empty). On EL8
# (systemd 239) ExecCondition is ignored and the agent runs as before; the
# Logs.Console=n setting above keeps the console quiet in that case.
cat > /etc/systemd/system/waagent.service.d/10-azure-only.conf << 'EOF'
[Service]
ExecCondition=/bin/sh -c 'test "$(cat /sys/class/dmi/id/chassis_asset_tag 2>/dev/null)" = "7783-7084-3265-9085-8269-3286-77"'
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