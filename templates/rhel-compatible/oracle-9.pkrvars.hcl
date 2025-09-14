# Oracle Linux 9 variables for rhel-base.pkr.hcl
template = "oracle-9"
distro_name = "Oracle Linux"

# Oracle Linux 9.4 (latest as of 2024)
iso_name = "OracleLinux-R9-U4-x86_64-dvd.iso"
iso_url = "https://yum.oracle.com/ISOS/OracleLinux/OL9/u4/x86_64/OracleLinux-R9-U4-x86_64-dvd.iso"
iso_checksum = "sha256:a7b6c5d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5"

# Boot command for Oracle Linux 9 with kickstart
boot_command = [
  "<tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter><wait>"
]

# Default settings
hostname = "oracle9"
username = "admin"
password = "admin"
boot_wait = "10s"