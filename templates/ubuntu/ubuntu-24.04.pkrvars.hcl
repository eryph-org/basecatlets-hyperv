template = "ubuntu-24.04"
mirror_directory = "24.04"
boot_wait = "3s"
iso_name = "ubuntu-24.04.2-live-server-amd64.iso"
iso_checksum = "sha256:D6DAB0C3A657988501B4BD76F1297C053DF710E06E0C3AECE60DEAD24F270B4D"
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