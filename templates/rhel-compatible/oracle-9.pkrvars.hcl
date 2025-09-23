# Oracle Linux 9 variables for rhel-base.pkr.hcl
template = "oracle-9"
distro_name = "Oracle Linux"

# Oracle Linux 9.5
iso_name = "OracleLinux-R9-U5-x86_64-dvd.iso"
iso_url = "https://yum.oracle.com/ISOS/OracleLinux/OL9/u5/x86_64/OracleLinux-R9-U5-x86_64-dvd.iso"
iso_checksum = "sha256:C2FA76C502CF1D93DFBD084D494D963AB7EA0A6F5535A083B8547B34037E88E1"

# Boot command for Oracle Linux 9 with kickstart (UEFI for Hyper-V Gen 2)
boot_command = [
  "c",
  "setparams 'kickstart'<enter>",
  "linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL-9-5-0-BaseOS-x86_64 inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>",
  "initrdefi /images/pxeboot/initrd.img<enter>",
  "boot<enter>"
]

# Default settings
hostname = "oracle9"
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
