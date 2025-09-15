# AlmaLinux 10 variables for rhel-base.pkr.hcl
template = "almalinux-10"
distro_name = "AlmaLinux"

# AlmaLinux 10.0 (new major release)
iso_name = "AlmaLinux-10.0-x86_64-dvd.iso"
iso_url = "https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10.0-x86_64-dvd.iso"
iso_checksum = "sha256:6c443f462b3993d15192a7c43ba8dfa3f232514db47d38796dab007a7455ae1a"

# Boot command for AlmaLinux 10 with kickstart (UEFI for Hyper-V Gen 2)
boot_command = [
  "c",
  "setparams 'kickstart'<enter>",
  "linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=AlmaLinux-10-0-x86_64-dvd inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>",
  "initrdefi /images/pxeboot/initrd.img<enter>",
  "boot<enter>"
]

# Default settings
hostname = "almalinux10"
username = "packer"
password = "packer"
boot_wait = "10s"

# Kernel configuration - use standard RHEL-compatible kernel
kernel_packages = "kernel\nkernel-devel"
kernel_exclusions = ""
distro_specific_post = ""