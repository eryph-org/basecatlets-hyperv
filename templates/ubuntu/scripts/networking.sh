#!/bin/sh -eux

ubuntu_version="`lsb_release -r | awk '{print $2}'`";
major_version="`echo $ubuntu_version | awk -F. '{print $1}'`";

exit 0;  # disable for now as it breaks the build

if [ $major_version = "20" ]
then 
    # Disable Predictable Network Interface names and use eth0
    sed -i 's/en[[:alnum:]]*/eth0/g' /etc/network/interfaces;
    sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 \1"/g' /etc/default/grub;
    update-grub;

fi