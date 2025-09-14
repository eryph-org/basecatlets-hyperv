#!/bin/bash -eux

# Cleanup script for RHEL-compatible distributions
# Cleans up temporary files, caches, and prepares the system for imaging

echo "Starting system cleanup..."

# Determine package manager
if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

# Clean package manager caches
echo "Cleaning package manager caches..."
$PKG_MGR clean all
rm -rf /var/cache/yum/*
rm -rf /var/cache/dnf/*

# Remove package manager metadata
find /var/lib/yum -name "*.sqlite" -delete 2>/dev/null || true
find /var/lib/dnf -name "*.sqlite" -delete 2>/dev/null || true

# Clean up log files
echo "Cleaning log files..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.log.*" -delete
rm -f /var/log/wtmp
rm -f /var/log/btmp
> /var/log/lastlog

# Clean up audit logs
rm -f /var/log/audit/audit.log*

# Clean up journal logs
journalctl --flush --rotate
journalctl --vacuum-time=1s

# Clean up temporary directories
echo "Cleaning temporary directories..."
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /root/.cache

# Clean up SSH keys (will be regenerated on first boot)
echo "Removing SSH host keys (will be regenerated)..."
rm -f /etc/ssh/ssh_host_*

# Clean up network interface persistence
echo "Cleaning network configuration..."
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/75-persistent-net-generator.rules

# Clean up NetworkManager connections
rm -rf /etc/NetworkManager/system-connections/*
rm -f /var/lib/NetworkManager/NetworkManager.state

# Clean up DHCP leases
rm -f /var/lib/dhcp/dhclient*.leases
rm -f /var/lib/NetworkManager/dhclient*.lease

# Clean up cloud-init state
echo "Cleaning cloud-init state..."
cloud-init clean --logs --seed || true
rm -rf /var/lib/cloud/instances/*
rm -rf /var/lib/cloud/instance
rm -rf /var/lib/cloud/data
rm -f /var/lib/cloud/sem/*

# Clean up machine-id (will be regenerated)
echo "Cleaning machine-id..."
> /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clean up systemd journal
rm -rf /var/log/journal/*
rm -f /var/lib/systemd/random-seed

# Clean up user accounts
echo "Cleaning user account artifacts..."
rm -f /root/.bash_history
rm -f /root/.viminfo
rm -f /root/.lesshst
rm -rf /root/.ssh
rm -f /home/*/.bash_history 2>/dev/null || true

# Clean up mail
rm -f /var/spool/mail/*
rm -f /var/mail/*

# Clean up cron
rm -f /var/spool/cron/*

# Clean up at jobs
rm -f /var/spool/at/*

# Clean up printer queues
rm -f /var/spool/cups/*

# Remove leftover packages
echo "Cleaning up leftover packages..."
$PKG_MGR autoremove -y || true

# Clean up kernel-related files that might cause issues
rm -f /boot/grub2/grubenv.rpmsave

# Remove anaconda-related files
rm -f /root/anaconda-ks.cfg
rm -f /root/original-ks.cfg
rm -rf /var/log/anaconda

# Clean up RPM database
echo "Cleaning RPM database..."
rpm --rebuilddb

# Clean up locate database
rm -f /var/lib/locate/locatedb
rm -f /var/lib/mlocate/mlocate.db

# Clean up man page cache
rm -rf /var/cache/man/*

# Clean up font cache
rm -rf /var/cache/fontconfig/*

# Clean up SSL certificates cache
rm -rf /var/cache/ca-certificates/*

# Zero out swap if it exists
echo "Checking for swap..."
swapoff -a || true

# Clean up history files
history -c
> ~/.bash_history

# Sync and prepare for shutdown
echo "Syncing filesystems..."
sync

# Clear free space (optional - can be enabled for better compression)
# Uncomment the following lines if you want to zero free space for better image compression
# This can take a long time depending on disk size
# echo "Zeroing free space for better compression (this may take a while)..."
# dd if=/dev/zero of=/EMPTY bs=1M || true
# rm -f /EMPTY

echo "System cleanup completed successfully"
echo "System is ready for imaging"