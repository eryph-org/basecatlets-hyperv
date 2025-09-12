#!/bin/sh -eux

# Azure Linux Agent installation and configuration - Azure-specific only
# This ensures Linux VMs are always Azure-compatible while working with cloud-init

echo "Installing and configuring Azure Linux Agent..."

# Install Azure Linux Agent and required packages
apt-get install -y walinuxagent cloud-utils-growpart gdisk hyperv-daemons

# Configure waagent to work with cloud-init (auto-detection mode)
# This allows both eryph and Azure to work with the same image
mkdir -p /etc/waagent.conf.d
cat > /etc/waagent.conf.d/99-azure.conf << 'EOF'
# Configure WALinuxAgent for cloud-init cooperation
Provisioning.Agent=auto
Provisioning.UseCloudInit=y

# Resource disk configuration (Azure temporary disk)
ResourceDisk.Format=y
ResourceDisk.EnableSwap=n
ResourceDisk.MountPoint=/mnt/resource
ResourceDisk.MountOptions=None

# Enable monitoring and extensions
Provisioning.MonitorHostName=y
Extensions.Enabled=y

# Network configuration
Provisioning.DecodeCustomData=n
Provisioning.ExecuteCustomData=n
EOF

# Enable waagent service (will start automatically on Azure)
systemctl enable waagent.service

# Don't start waagent now - it will start automatically when deployed to Azure
# For eryph, cloud-init handles provisioning and waagent remains dormant
echo "Azure Linux Agent installed and configured for universal compatibility"