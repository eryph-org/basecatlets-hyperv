# AlmaLinux 9 variables for rhel-base.pkr.hcl
template = "almalinux-9"
distro_name = "AlmaLinux"

# AlmaLinux 9.4 (latest as of 2024)
iso_name = "AlmaLinux-9.4-x86_64-dvd.iso"
iso_url = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.4-x86_64-dvd.iso"
iso_checksum = "sha256:1e7c5d7b9e4f8e7c3a6b2c5d1f9e8a7b6c5d4e3f2a1b9c8d7e6f5a4b3c2d1e0"

# Boot command for AlmaLinux 9 with kickstart
boot_command = [
  "<tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter><wait>"
]

# Default settings
hostname = "almalinux9"
username = "admin"
password = "admin"
boot_wait = "10s"