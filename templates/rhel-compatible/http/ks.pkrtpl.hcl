# Generic kickstart template for RHEL-compatible distributions
# Uses Packer templating to customize for different distributions

# System configuration
text
skipx
lang en_US.UTF-8
keyboard us
timezone UTC --utc

# Network configuration - DHCP for all interfaces
network --bootproto=dhcp --onboot=yes --device=eth0 --hostname=${hostname}

# Security settings
firewall --disabled
selinux --permissive
authselect --enableshadow --passalgo=sha512

# Root password
rootpw --iscrypted ${password_hash}

# Create user
user --name=${username} --groups=wheel --iscrypted --password=${password_hash}

# Disk partitioning - Azure/Hyper-V optimized
# No swap partition (per Azure best practices)
# Simple layout for maximum compatibility and expandability
zerombr
clearpart --all --initlabel
part /boot/efi --fstype=efi --size=200 --asprimary
part /boot --fstype=xfs --size=1024 --asprimary
part / --fstype=xfs --size=1 --grow --asprimary

# Bootloader configuration - Microsoft Azure/Hyper-V requirements
bootloader --location=mbr --append="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0 net.ifnames=0 rootdelay=300"

# Package selection
${package_list}

# Services configuration
services --enabled=sshd,NetworkManager,cloud-init,cloud-final,cloud-config,cloud-init-local

# Post-installation configuration
%post --log=/var/log/anaconda-post.log

# Configure sudo for user without password
echo "${username} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${username}

# Enable SSH root login temporarily for Packer
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Configure cloud-init for NoCloud and Azure datasources
mkdir -p /etc/cloud/cloud.cfg.d

# Multi-datasource configuration for Eryph (NoCloud) and Azure
cat > /etc/cloud/cloud.cfg.d/91-nocloud_azure_datasource.cfg << 'EOF'
datasource_list:
  - NoCloud
  - Azure
  - None
datasource:
  Azure:
    apply_network_config: false
    data_dir: /var/lib/waagent
EOF

# Hyper-V KVP logging configuration
cat > /etc/cloud/cloud.cfg.d/10-azure-kvp.cfg << 'EOF'
reporting:
  logging:
    type: log
  telemetry:
    type: hyperv
EOF

# Disable cloud-init network configuration to avoid conflicts
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# Configure WALinuxAgent for cloud-init compatibility
if [ -f /etc/waagent.conf ]; then
    # Disable provisioning (let cloud-init handle it)
    sed -i 's/Provisioning.Enabled=y/Provisioning.Enabled=n/g' /etc/waagent.conf
    sed -i 's/Provisioning.UseCloudInit=n/Provisioning.UseCloudInit=y/g' /etc/waagent.conf
    # Disable resource disk formatting (let cloud-init handle it)
    sed -i 's/ResourceDisk.Format=y/ResourceDisk.Format=n/g' /etc/waagent.conf
    sed -i 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/g' /etc/waagent.conf
fi

# Enable services
systemctl enable cloud-init cloud-config cloud-final cloud-init-local
systemctl enable waagent
systemctl enable NetworkManager
systemctl enable sshd

# Configure Hyper-V integration services
if [ -f /etc/systemd/system.conf ]; then
    echo "DefaultTimeoutStartSec=300s" >> /etc/systemd/system.conf
    echo "DefaultTimeoutStopSec=300s" >> /etc/systemd/system.conf
fi

${distro_specific_post}

# Ensure proper permissions
chmod 600 /etc/sudoers.d/${username}

%end

# Reboot after installation
reboot