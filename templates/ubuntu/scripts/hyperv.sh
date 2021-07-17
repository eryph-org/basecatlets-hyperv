#!/bin/sh -eux
ubuntu_version="`lsb_release -r | awk '{print $2}'`";
major_version="`echo $ubuntu_version | awk -F. '{print $1}'`";

# gen 2 EFI fix - see https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/supported-ubuntu-virtual-machines-on-hyper-v
cp -r /boot/efi/EFI/ubuntu/ /boot/efi/EFI/boot
if [ -f /boot/efi/EFI/boot/shimx64.efi ]; then
  mv /boot/efi/EFI/boot/shimx64.efi /boot/efi/EFI/boot/bootx64.efi
fi