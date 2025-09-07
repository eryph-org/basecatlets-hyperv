#!/bin/sh -eux

echo "Ensuring cloud-init is installed and reset for repacking"

# Ensure cloud-init is installed
if ! dpkg -l | grep -q cloud-init; then
    echo "Installing cloud-init..."
    apt-get update
    apt-get -y install cloud-init
else
    echo "cloud-init already installed"
fi

# Stop cloud-init services
systemctl stop cloud-init.service cloud-init-local.service cloud-config.service cloud-final.service 2>/dev/null || true

# Remove existing cloud-init artifacts
echo "Cleaning cloud-init state..."
cloud-init clean --logs --seed

# Remove instance-specific data
rm -rf /var/lib/cloud/instances/*
rm -rf /var/lib/cloud/instance
rm -f /var/lib/cloud/data/result.json
rm -f /var/lib/cloud/data/status.json

# Remove machine-id to force regeneration
echo "Resetting machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Remove SSH host keys (will be regenerated on first boot)
echo "Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# Remove any existing network configuration that might have been created by cloud-init
rm -f /etc/netplan/50-cloud-init.yaml 2>/dev/null || true
rm -f /etc/network/interfaces.d/50-cloud-init.cfg 2>/dev/null || true

# Reset hostname to generic
echo "localhost" > /etc/hostname
sed -i '/^127.0.1.1/d' /etc/hosts

# Remove any user-specific cloud-init config
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg

# Ensure cloud-init is enabled for next boot
systemctl enable cloud-init.service cloud-init-local.service cloud-config.service cloud-final.service 2>/dev/null || true

echo "cloud-init reset completed"