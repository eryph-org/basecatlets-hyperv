#!/bin/bash
set -euo pipefail

echo "=== Setting up Hyper-V integration ==="

# The hyperv-packages.json should already be installed via PackageLists
# This script only does additional configuration that can't be done via packages

# Enable Hyper-V services via systemd presets (works in chroot)
mkdir -p /usr/lib/systemd/system-preset
cat > /usr/lib/systemd/system-preset/90-hyperv.preset << 'EOF'
# Enable Hyper-V integration services
enable hv-fcopy-daemon.service
enable hv-kvp-daemon.service
enable hv-vss-daemon.service
EOF

echo "✓ Hyper-V integration services configured"