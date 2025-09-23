# AlmaLinux 9 variables for rhel-base.pkr.hcl
template = "almalinux-9"
distro_name = "AlmaLinux"

# AlmaLinux 9.6 (current as of 2024)
iso_name = "AlmaLinux-9.6-x86_64-dvd.iso"
iso_url = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.6-x86_64-dvd.iso"
iso_checksum = "sha256:db7b45e071b6319d43781eb8d9bec9b8d6b0ac41ad5e49db7fe113c76f0d2ca2"

# Boot command for AlmaLinux 9 with kickstart (UEFI for Hyper-V Gen 2)
boot_command = [
  "c",
  "setparams 'kickstart'<enter>",
  "linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=AlmaLinux-9-6-x86_64-dvd inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>",
  "initrdefi /images/pxeboot/initrd.img<enter>",
  "boot<enter>"
]

# Default settings
hostname = "almalinux9"
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