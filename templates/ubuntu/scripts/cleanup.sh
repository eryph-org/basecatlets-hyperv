#!/bin/sh -eux

echo "remove linux-headers"
dpkg --list \
  | awk '{ print $2 }' \
  | grep 'linux-headers' \
  | xargs apt-get -y purge;

echo "remove specific Linux kernels, such as linux-image-3.11.0-15-generic but keeps the current kernel and does not touch the virtual packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep 'linux-image-.*-generic' \
    | grep -v `uname -r` \
    | xargs apt-get -y purge;

echo "remove old kernel modules packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep 'linux-modules-.*-generic' \
    | grep -v `uname -r` \
    | xargs apt-get -y purge;

echo "remove linux-source package"
dpkg --list \
    | awk '{ print $2 }' \
    | grep linux-source \
    | xargs apt-get -y purge;

echo "remove all development packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-dev\(:[a-z0-9]\+\)\?$' \
    | grep -v -- 'systemd-dev' \
    | xargs apt-get -y purge;

echo "remove docs packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-doc$' \
    | xargs apt-get -y purge;

echo "remove X11 libraries"
apt-get -y purge libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6;

echo "remove obsolete networking packages"
apt-get -y purge ppp pppconfig pppoeconf;

echo "remove packages we don't need"
apt-get -y purge popularity-contest command-not-found friendly-recovery bash-completion  laptop-detect motd-news-config usbutils grub-legacy-ec2

# 21.04+ don't have this
echo "remove the installation-report"
apt-get -y purge popularity-contest installation-report fonts-ubuntu-font-family-console || true;

echo "remove the console font"
apt-get -y purge fonts-ubuntu-console || true;

echo "removing command-not-found-data"
# 19.10+ don't have this package so fail gracefully
apt-get -y purge command-not-found-data || true;

# Exclude the files we don't need w/o uninstalling linux-firmware
echo "Setup dpkg excludes for linux-firmware"
cat <<_EOF_ | cat >> /etc/dpkg/dpkg.cfg.d/excludes
#ERYPH-BEGIN
path-exclude=/lib/firmware/*
path-exclude=/usr/share/doc/linux-firmware/*
#ERYPH-END
_EOF_

echo "delete the massive firmware files"
rm -rf /lib/firmware/*
rm -rf /usr/share/doc/linux-firmware/*

echo "autoremoving packages and cleaning apt data"
apt-get -y autoremove;
apt-get -y clean;

echo "remove /usr/share/doc/"
rm -rf /usr/share/doc/*

echo "remove /var/cache"
find /var/cache -type f -exec rm -rf {} \;

echo "truncate any logs that have built up during the install"
find /var/log -type f -exec truncate --size=0 {} \;

echo "blank netplan machine-id (DUID) so machines get unique ID generated on boot"
truncate -s 0 /etc/machine-id

# Remove machine-specific SSH keys (will be regenerated on first boot)
echo "remove SSH host keys for security (regenerated on first boot)"
rm -f /etc/ssh/ssh_host_*

# Clear machine-specific D-Bus machine ID
rm -f /var/lib/dbus/machine-id

echo "remove the contents of /tmp and /var/tmp"
rm -rf /tmp/* /var/tmp/*

echo "force a new random seed to be generated"
rm -f /var/lib/systemd/random-seed

# Ensure Hyper-V modules are loaded for all hypervisor environments
echo "ensure Hyper-V modules are configured for loading"
cat >> /etc/modules << 'EOF'
# Hyper-V modules for cloud/hypervisor compatibility
hv_vmbus
hv_netvsc
hv_storvsc
hv_utils
hv_balloon
EOF

# Configure initramfs to include Hyper-V drivers
cat >> /etc/initramfs-tools/modules << 'EOF'
# Hyper-V modules for cloud compatibility
hv_vmbus
hv_netvsc
hv_storvsc
hv_utils
hv_balloon
EOF

# Update initramfs
echo "updating initramfs with Hyper-V modules"
update-initramfs -u

# Enable NTP for accurate time synchronization (critical for cloud)
echo "enabling NTP time synchronization"
timedatectl set-ntp true

# Optimize systemd services for cloud boot
systemctl enable systemd-networkd-wait-online.service
systemctl enable systemd-timesyncd.service

# Configure systemd to handle cloud metadata properly
mkdir -p /etc/systemd/system/cloud-init-local.service.d
cat > /etc/systemd/system/cloud-init-local.service.d/cloud-init-local.conf << 'EOF'
[Unit]
# Ensure cloud-init runs early enough for proper initialization
Before=systemd-networkd.service
EOF

# Ensure proper permissions on cloud-init directories
chmod 700 /var/lib/cloud
chmod 755 /etc/cloud

echo "clear the history so our install isn't there"
rm -f /root/.wget-hsts
export HISTSIZE=0
