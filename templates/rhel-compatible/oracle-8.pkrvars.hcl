# Oracle Linux 8 variables for rhel-base.pkr.hcl
template = "oracle-8"
distro_name = "Oracle Linux"

# Oracle Linux 8.9
iso_name = "OracleLinux-R8-U9-x86_64-dvd.iso"
iso_url = "https://yum.oracle.com/ISOS/OracleLinux/OL8/u9/x86_64/OracleLinux-R8-U9-x86_64-dvd.iso"
iso_checksum = "sha256:PLACEHOLDER_CHECKSUM_VERIFY_FROM_ORACLE_CHECKSUM_FILE"

# Boot command for Oracle Linux 8 with kickstart (UEFI for Hyper-V Gen 2)
boot_command = [
  "c",
  "setparams 'kickstart'<enter>",
  "linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL-8-9-0-BaseOS-x86_64 inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>",
  "initrdefi /images/pxeboot/initrd.img<enter>",
  "boot<enter>"
]

# Default settings
hostname = "oracle8"
username = "packer"
password = "packer"
boot_wait = "10s"

# Package list for Oracle Linux (full configuration)
package_list = <<-EOF
%packages --ignoremissing
@core
@base
cloud-init
cloud-utils-growpart
hyperv-daemons
WALinuxAgent
kernel
kernel-uek
kernel-uek-devel
grub2-efi-x64
efibootmgr
shim-x64
sudo
python3
python3-pip
wget
curl
openssh-server
NetworkManager
# Remove unnecessary packages
-plymouth
-plymouth-core-libs
-plymouth-scripts
-NetworkManager-team
-NetworkManager-tui
-kernel
-kernel-devel
%end
EOF

distro_specific_post = "# Set UEK kernel as default boot option\ngrub2-set-default 0"

# Kernel configuration - use UEK kernel (Microsoft recommended for Oracle Linux)
kernel_packages = "kernel-uek\nkernel-uek-devel"
kernel_exclusions = "-kernel\n-kernel-devel"
distro_specific_post = "# Set UEK kernel as default boot option\ngrub2-set-default 0"