# AlmaLinux 8 variables for rhel-base.pkr.hcl
template = "almalinux-8"
distro_name = "AlmaLinux"

# AlmaLinux 8.10 (current as of 2024)
iso_name = "AlmaLinux-8.10-x86_64-dvd.iso"
iso_url = "https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8.10-x86_64-dvd.iso"
iso_checksum = "sha256:463fa92155b886e31627f6713e1c2824343762245a914715ffd6f2efc300b7a1"

# Boot command for AlmaLinux 8 with kickstart (UEFI for Hyper-V Gen 2)
boot_command = [
  "c",
  "setparams 'kickstart'<enter>",
  "linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=AlmaLinux-8-10-x86_64-dvd inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>",
  "initrdefi /images/pxeboot/initrd.img<enter>",
  "boot<enter>"
]

# Default settings
hostname = "almalinux8"
username = "packer"
password = "packer"
boot_wait = "10s"

# Package list for AlmaLinux (minimal configuration following official Azure image)
package_list = <<-EOF
%packages --ignoremissing
dracut-config-generic
grub2-pc
tar
rsyslog-logrotate
-*firmware
-dracut-config-rescue
-firewalld
cloud-init
cloud-utils-growpart
# C libraries required for .NET self-contained apps (eryph-guest-services)
glibc
libgcc
libstdc++
libicu
%end

# disable kdump service
%addon com_redhat_kdump --disable
%end
EOF

# Kernel configuration - use standard RHEL-compatible kernel
kernel_packages = "kernel\nkernel-devel"
kernel_exclusions = ""
distro_specific_post = ""