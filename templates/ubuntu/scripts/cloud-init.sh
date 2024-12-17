#!/bin/sh

# install cloud-init
apt-get -y install cloud-init

#hostname will be managed by cloud-init, but the current value will not be removed
HOSTNAME=`hostname`
sed -i "/${HOSTNAME}/d" /etc/hosts

rm /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f -- /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg

cloud-init clean