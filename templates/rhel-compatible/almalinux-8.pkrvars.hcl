# AlmaLinux 8 variables for rhel-base.pkr.hcl
template = "almalinux-8"
distro_name = "AlmaLinux"

# AlmaLinux 8.10 (latest as of 2024)
iso_name = "AlmaLinux-8.10-x86_64-dvd.iso"
iso_url = "https://repo.almalinux.org/almalinux/8/isos/x86_64/AlmaLinux-8.10-x86_64-dvd.iso"
iso_checksum = "sha256:be7d0d6e0ec6c4c02d67691d6cd3e44e0e2b5a2c5b6f4c0b9e0f2e0c1a5b4e7d"

# Boot command for AlmaLinux 8 with kickstart
boot_command = [
  "<tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter><wait>"
]

# Default settings
hostname = "almalinux8"
username = "admin"
password = "admin"
boot_wait = "10s"