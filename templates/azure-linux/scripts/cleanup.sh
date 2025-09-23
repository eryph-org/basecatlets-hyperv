#!/bin/bash
set -euo pipefail

echo "=== System cleanup ==="

# Clean package cache
if command -v dnf >/dev/null 2>&1; then
    dnf clean all
fi

if command -v yum >/dev/null 2>&1; then
    yum clean all
fi

# Clean logs
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean SSH host keys (will be regenerated on first boot)
rm -f /etc/ssh/ssh_host_*

# Clean machine-id (will be regenerated on first boot)
echo -n > /etc/machine-id

# Clean bash history
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# Clean cache directories
rm -rf /var/cache/*
rm -rf /root/.cache

echo "✓ System cleanup completed"