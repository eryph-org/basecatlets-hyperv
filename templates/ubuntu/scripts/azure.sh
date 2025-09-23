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

# Logs
Logs.Verbose=n
OS.AllowHTTP=n
OS.CheckRdmaDriver=n
EOF

# Enable walinuxagent service (will start automatically on Azure)
systemctl enable walinuxagent.service
