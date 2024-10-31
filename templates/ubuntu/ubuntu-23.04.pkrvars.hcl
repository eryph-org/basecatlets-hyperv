template = "ubuntu-23.04"
mirror_directory = "23.04"
boot_wait = "3s"
iso_name = "ubuntu-23.04-live-server-amd64.iso"
iso_checksum = "sha256:c7cda48494a6d7d9665964388a3fc9c824b3bef0c9ea3818a1be982bc80d346b"
boot_cmds = [
    " <wait>", 
    " <wait>", 
    " <wait>", 
    " <wait>", 
    " <wait>", 
    "c", 
    "<wait>", 
    "set gfxpayload=keep", 
    "<enter><wait>", 
    "linux /casper/vmlinuz quiet<wait>", 
    " autoinstall<wait>", 
    " ds=nocloud-net<wait>", 
    "\\;s=http://<wait>", 
    "{{ .HTTPIP }}<wait>", 
    ":{{ .HTTPPort }}/<wait>", 
    " ---", "<enter><wait>", 
    "initrd /casper/initrd<wait>", 
    "<enter><wait>", 
    "boot<enter><wait>"
    ]