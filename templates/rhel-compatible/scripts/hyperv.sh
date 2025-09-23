#!/bin/bash -eux

# Hyper-V integration services configuration for RHEL-compatible distributions
# Optimizes the VM for Hyper-V environments

echo "Configuring Hyper-V integration services..."

# Ensure hyperv-daemons package is installed
if command -v dnf >/dev/null 2>&1; then
    dnf install -y hyperv-daemons
else
    yum install -y hyperv-daemons
fi

# Enable all Hyper-V services
systemctl enable hypervkvpd.service || echo "hypervkvpd not found"
systemctl enable hypervvssd.service || echo "hypervvssd not found"
systemctl enable hypervfcopyd.service || echo "hypervfcopyd not found"

# Configure Hyper-V modules to load at boot
cat > /etc/modules-load.d/hyperv.conf << 'EOF'
hv_vmbus
hv_storvsc
hv_netvsc
hv_balloon
hv_utils
EOF

# Configure kernel parameters for Hyper-V optimization
cat > /etc/sysctl.d/99-hyperv.conf << 'EOF'
# Hyper-V optimizations
kernel.sysrq = 1
vm.swappiness = 1
EOF

# Configure dracut to include Hyper-V drivers (Microsoft requirement)
cat > /etc/dracut.conf.d/99-hyperv.conf << 'EOF'
add_drivers+=" hv_vmbus hv_netvsc hv_storvsc "
EOF

# Regenerate initramfs to include Hyper-V drivers
if command -v dracut >/dev/null 2>&1; then
    dracut -f
fi

# Configure GRUB for Hyper-V console access (Microsoft Azure/Hyper-V requirements)
if [ -f /etc/default/grub ]; then
    # Update GRUB configuration for serial console - exact Microsoft specifications
    sed -i 's/GRUB_CMDLINE_LINUX="[^"]*/& console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0 net.ifnames=0/' /etc/default/grub

    # Remove quiet and rhgb for better debugging (Microsoft requirement)
    sed -i 's/ quiet//g' /etc/default/grub
    sed -i 's/ rhgb//g' /etc/default/grub
    sed -i 's/ crashkernel=auto//g' /etc/default/grub

    # Update GRUB timeout for faster boot
    sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub

    # Regenerate GRUB configuration
    if [ -f /boot/efi/EFI/*/grub.cfg ]; then
        grub2-mkconfig -o /boot/efi/EFI/*/grub.cfg || grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
fi

# Add Microsoft-required udev rule for memory hot-add (Hyper-V Dynamic Memory)
cat > /etc/udev/rules.d/100-balloon.rules << 'EOF'
SUBSYSTEM=="memory", ACTION=="add", ATTR{state}="online"
EOF

# Add Azure Accelerated Networking udev rule (Azure compatibility)
cat > /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules << 'EOF'
# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
# This interface is transparently bonded to the synthetic interface,
# so NetworkManager should just ignore any SRIOV interfaces.
SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"
EOF

# Configure rsyslog for Hyper-V logging
if [ -f /etc/rsyslog.conf ]; then
    echo '# Log Hyper-V messages' >> /etc/rsyslog.conf
    echo 'kern.info                               /var/log/hyperv' >> /etc/rsyslog.conf
fi

# Configure logrotate for Hyper-V logs
cat > /etc/logrotate.d/hyperv << 'EOF'
/var/log/hyperv {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF

# Set up udev rules for Hyper-V devices
cat > /etc/udev/rules.d/99-hyperv.rules << 'EOF'
# Hyper-V device rules
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="hv_netvsc", KERNEL=="eth*", NAME="eth%n"
SUBSYSTEM=="block", ACTION=="add", DRIVERS=="hv_storvsc", KERNEL=="sd*", NAME="sd%n"
EOF

echo "Hyper-V configuration completed successfully"