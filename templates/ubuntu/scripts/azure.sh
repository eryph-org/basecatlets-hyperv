#!/bin/sh -eux

# Azure Linux Agent installation and configuration - Azure-specific only
# This ensures Linux VMs are always Azure-compatible while working with cloud-init

echo "Installing and configuring Azure Linux Agent..."

# Install Azure Linux Agent and required packages
apt-get install -y walinuxagent cloud-guest-utils

# Configure waagent to work with cloud-init
# This allows both eryph and Azure to work with the same image
cat > /etc/waagent.conf << 'EOF'
# WALinuxAgent configuration for Ubuntu with cloud-init
# Modern configuration for 2024+ compatibility

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

# Logs
Logs.Verbose=n
Logs.Console=n
OS.AllowHTTP=n
OS.CheckRdmaDriver=n
EOF

# Enable walinuxagent service (will start automatically on Azure)
systemctl enable walinuxagent.service

# Gate the agent to Azure-only. Off-Azure (eryph/Hyper-V) cloud-init does all
# provisioning and the agent would otherwise retry the Azure wireserver
# (168.63.129.16) forever. ExecCondition exits the unit silently when the Azure
# DMI chassis asset tag is absent (generic Hyper-V leaves it empty). Needs
# systemd >= 243 (all supported Ubuntu).
mkdir -p /etc/systemd/system/walinuxagent.service.d
cat > /etc/systemd/system/walinuxagent.service.d/10-azure-only.conf << 'EOF'
[Service]
ExecCondition=/bin/sh -c 'test "$(cat /sys/class/dmi/id/chassis_asset_tag 2>/dev/null)" = "7783-7084-3265-9085-8269-3286-77"'
EOF
