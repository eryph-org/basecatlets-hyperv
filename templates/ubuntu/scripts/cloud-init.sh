#!/bin/sh

# Install cloud-init
echo "Installing cloud-init..."

# install cloud-init
apt-get -y install cloud-init

#hostname will be managed by cloud-init, but the current value will not be removed
HOSTNAME=`hostname`
sed -i "/${HOSTNAME}/d" /etc/hosts

rm /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f -- /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg

# Configure cloud-init for Azure datasource compatibility
# This ensures the image works on both eryph and Azure
cat > /etc/cloud/cloud.cfg.d/91-nocloud_azure_datasource.cfg << 'EOF'
datasource_list: [ NoCloud, Azure, None ]
datasource:
  Azure:
    apply_network_config: false
    data_dir: /var/lib/waagent
EOF

cat > /etc/cloud/cloud.cfg.d/92-reporting.cfg << 'EOF'
reporting:
  logging:
    type: log
  telemetry:
    type: hyperv
EOF


cloud-init clean