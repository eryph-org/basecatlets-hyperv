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

# Install essential packages not in minimal kickstart
$PKG_MGR install -y \
    openssh-server \
    cloud-init \
    hyperv-daemons \
    WALinuxAgent \
    sudo \
    curl \
    wget \
    rsync \
    unzip \
    vim-minimal \
    bash-completion \
    psmisc \
    glibc \
    libgcc \
    libstdc++ \
    libicu

# Ensure services are enabled
systemctl enable cloud-init
systemctl enable cloud-init-local
systemctl enable cloud-config
systemctl enable cloud-final
systemctl enable waagent
systemctl enable hypervkvpd || echo "hypervkvpd service not found"
systemctl enable hypervvssd || echo "hypervvssd service not found"

echo "System update completed successfully"