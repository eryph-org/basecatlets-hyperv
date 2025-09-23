# Oracle Linux 10 variables for rhel-base.pkr.hcl
template = "oracle-10"
distro_name = "Oracle Linux"

# Oracle Linux 10.0
iso_name = "OracleLinux-R10-U0-x86_64-dvd.iso"
iso_url = "https://yum.oracle.com/ISOS/OracleLinux/OL10/u0/x86_64/OracleLinux-R10-U0-x86_64-dvd.iso"
iso_checksum = "sha256:PLACEHOLDER_CHECKSUM_VERIFY_FROM_ORACLE_CHECKSUM_FILE"

# Boot command for Oracle Linux 10 with kickstart (UEFI for Hyper-V Gen 2)
boot_command = [
  "c",
  "setparams 'kickstart'<enter>",
  "linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL-10-0-0-BaseOS-x86_64 inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>",
  "initrdefi /images/pxeboot/initrd.img<enter>",
  "boot<enter>"
]

# Default settings
hostname = "oracle10"
username = "packer"
password = "packer"
boot_wait = "10s"

# Kernel configuration - use UEK kernel (Microsoft recommended for Oracle Linux)
kernel_packages = "kernel-uek\nkernel-uek-devel"
kernel_exclusions = "-kernel\n-kernel-devel"
distro_specific_post = "# Set UEK kernel as default boot option\ngrub2-set-default 0"