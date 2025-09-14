#!/bin/bash -eux

# Network configuration script for RHEL-compatible distributions
# Optimizes networking for cloud/virtual environments

echo "Configuring network settings..."

# Configure NetworkManager for cloud environments
cat > /etc/NetworkManager/conf.d/99-cloud.conf << 'EOF'
[main]
dns=default
rc-manager=file

[device]
wifi.scan-rand-mac-address=no

[connection]
connection.stable-id=${CONNECTION}/${BOOT}
EOF

# Disable NetworkManager wait-online service (causes boot delays in cloud)
systemctl disable NetworkManager-wait-online.service || true

# Configure sshd for cloud environments
sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/#GSSAPIAuthentication yes/GSSAPIAuthentication no/' /etc/ssh/sshd_config

# Enable SSH
systemctl enable sshd

# RHEL/CentOS uses NetworkManager for DNS, not systemd-resolved
# No additional DNS configuration needed

# Network performance optimizations for virtual environments
cat > /etc/sysctl.d/99-network-performance.conf << 'EOF'
# Network performance optimizations for virtual environments
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mtu_probing = 1
EOF

# Configure kernel module loading for network drivers
echo "8021q" >> /etc/modules-load.d/network.conf
echo "bridge" >> /etc/modules-load.d/network.conf

# Ensure proper hostname resolution
echo "127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4" > /etc/hosts
echo "::1       localhost localhost.localdomain localhost6 localhost6.localdomain6" >> /etc/hosts

echo "Network configuration completed successfully"