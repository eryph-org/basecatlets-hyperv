#!/bin/bash -eux

# System update script for RHEL-compatible distributions
# Works with AlmaLinux, Oracle Linux, RHEL, and other RHEL derivatives

echo "Starting system update..."

# Determine package manager (dnf preferred, fallback to yum)
if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

echo "Using package manager: $PKG_MGR"

# Update package cache and all packages
$PKG_MGR clean all
$PKG_MGR makecache
$PKG_MGR update -y

# Install EPEL repository if available (common for RHEL-compatible distros)
if ! $PKG_MGR list installed epel-release >/dev/null 2>&1; then
    echo "Installing EPEL repository..."
    $PKG_MGR install -y epel-release || echo "EPEL not available or already configured"
fi

# Update package cache after adding EPEL
$PKG_MGR makecache

# Install essential system tools for minimal cloud image
$PKG_MGR install -y \
    wget \
    curl \
    rsync \
    tar \
    unzip \
    vim-minimal \
    bash-completion \
    psmisc \
    which \
    sudo

# Install cloud and virtualization packages
echo "Installing cloud and virtualization packages..."
$PKG_MGR install -y \
    cloud-init \
    cloud-utils-growpart \
    hyperv-daemons \
    WALinuxAgent \
    python3 \
    python3-pip

# Ensure services are enabled
systemctl enable cloud-init
systemctl enable cloud-init-local
systemctl enable cloud-config
systemctl enable cloud-final
systemctl enable walinuxagent
systemctl enable hypervkvpd || echo "hypervkvpd service not found"
systemctl enable hypervvssd || echo "hypervvssd service not found"

echo "System update completed successfully"