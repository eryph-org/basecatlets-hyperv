template = "ubuntu-24.04"
mirror_directory = "24.04"
boot_wait = "3s"
iso_name = "ubuntu-24.04.1-live-server-amd64.iso"
iso_checksum = "sha256:e240e4b801f7bb68c20d1356b60968ad0c33a41d00d828e74ceb3364a0317be9"
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