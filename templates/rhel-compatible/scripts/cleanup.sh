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

# Reset DNF history (like AlmaLinux playbook)
echo "Resetting DNF history..."
rm -rf /var/lib/dnf/history* 2>/dev/null || true

# Clean up log files (matching AlmaLinux playbook)
echo "Cleaning log files..."
# Truncate specific system logs to 0 bytes
truncate -s 0 /var/log/audit/audit.log || true
truncate -s 0 /var/log/wtmp || true
truncate -s 0 /var/log/lastlog || true
truncate -s 0 /var/log/btmp || true
truncate -s 0 /var/log/cron || true
truncate -s 0 /var/log/maillog || true
truncate -s 0 /var/log/messages || true
truncate -s 0 /var/log/secure || true
truncate -s 0 /var/log/spooler || true
# Remove other log files
find /var/log -type f -name "*.log.*" -delete 2>/dev/null || true
find /var/log -name "*log" -name "*.old" -o -name "*.log.gz" -o -name "*.[0-9]" -o -name "*.gz" -delete 2>/dev/null || true

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
rm -rf /var/lib/cloud/sem/* 2>/dev/null || true

# Clean up machine-id and system info (will be regenerated)
echo "Cleaning machine-id and system info..."
truncate -s 0 /etc/machine-id || true
truncate -s 0 /etc/resolv.conf || true
rm -f /var/lib/dbus/machine-id
rm -f /etc/hostname || true
rm -f /etc/machine-info || true
rm -f /var/lib/systemd/credential.secret || true

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
rm -rf /var/spool/mail/* 2>/dev/null || true
rm -rf /var/mail/* 2>/dev/null || true

# Clean up cron
rm -rf /var/spool/cron/* 2>/dev/null || true

# Clean up at jobs
rm -rf /var/spool/at/* 2>/dev/null || true

# Clean up printer queues
rm -rf /var/spool/cups/* 2>/dev/null || true

# Remove old kernel versions (critical for size reduction)
echo "Removing old kernel versions..."
$PKG_MGR -y remove --oldinstallonly || true

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

# Clean up documentation and info pages
echo "Removing documentation and info pages..."
rm -rf /usr/share/doc/*
rm -rf /usr/share/info/*
rm -rf /usr/share/man/??_*
find /usr/share/man -type f -name "*.gz" -delete 2>/dev/null || true

# Clean up locale files (keep only en_US)
echo "Cleaning locale files..."
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en_US' -exec rm -rf {} + 2>/dev/null || true
find /usr/share/i18n/locales -mindepth 1 -maxdepth 1 ! -name 'en_US' -delete 2>/dev/null || true

# Remove development packages cache
rm -rf /usr/share/pixmaps/*
rm -rf /usr/share/icons/*/
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/wallpapers/*

# Clean up systemd unit file cache
rm -rf /var/lib/systemd/catalog/database
systemd-catalog update || true

# Remove more temporary files
rm -rf /root/.local/share/Trash/*
rm -rf /var/lib/yum/history/* 2>/dev/null || true
rm -rf /var/lib/dnf/history/* 2>/dev/null || true

# Zero out swap if it exists
echo "Checking for swap..."
swapoff -a || true

# Clean up history files
history -c
> ~/.bash_history

# Sync and prepare for shutdown
echo "Syncing filesystems..."
sync

# Randomize root password for security
echo "Randomizing root password..."
openssl rand -base64 32 | passwd --stdin root || true

# Deprovision WALinuxAgent if installed (like AlmaLinux playbook)
if [ -f /usr/sbin/waagent ]; then
    echo "Deprovisioning WALinuxAgent..."
    waagent -deprovision+user -force || true
fi

# Free space zeroing is handled by minimize.sh script

echo "System cleanup completed successfully"
echo "System is ready for imaging"