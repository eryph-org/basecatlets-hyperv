# Oracle Linux 8 variables for rhel-base.pkr.hcl
template = "oracle-8"
distro_name = "Oracle Linux"

# Oracle Linux 8.10 (latest as of 2024)
iso_name = "OracleLinux-R8-U10-x86_64-dvd.iso"
iso_url = "https://yum.oracle.com/ISOS/OracleLinux/OL8/u10/x86_64/OracleLinux-R8-U10-x86_64-dvd.iso"
iso_checksum = "sha256:f1b5e5b7d8c9e4f3a2b1c5d7e9f8a6b4c3d2e1f9a8b7c6d5e4f3a2b1c9d8e7f6"

# Boot command for Oracle Linux 8 with kickstart
boot_command = [
  "<tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter><wait>"
]

# Default settings
hostname = "oracle8"
username = "admin"
password = "admin"
boot_wait = "10s"