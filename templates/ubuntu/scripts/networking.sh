#!/bin/sh -eux

ubuntu_version="`lsb_release -r | awk '{print $2}'`";
major_version="`echo $ubuntu_version | awk -F. '{print $1}'`";

echo "Configuring network settings for cloud compatibility..."

# Configure GRUB for better console output and network naming
# This helps with debugging, remote access, and consistent naming in cloud environments
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0 earlyprintk=ttyS0 rootdelay=300 net.ifnames=0 biosdevname=0"/' /etc/default/grub

# Remove quiet and splash for better boot diagnostics
sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=""/' /etc/default/grub

# Set a reasonable timeout for GRUB
sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub

# Update GRUB configuration
update-grub

# Configure network settings for cloud environments
# Disable IPv6 if not needed (reduces attack surface and boot time)
cat >> /etc/sysctl.conf << 'EOF'

# Cloud networking optimizations
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Improve network performance
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
EOF

# Configure SSH for better cloud security
cat >> /etc/ssh/sshd_config << 'EOF'

# Cloud security optimizations
ClientAliveInterval 120
ClientAliveCountMax 2
UseDNS no
EOF

echo "Network configuration completed"