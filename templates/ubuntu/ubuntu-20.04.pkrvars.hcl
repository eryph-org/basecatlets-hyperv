
template = "ubuntu-20.04-amd64"
mirror_directory = "20.04"
boot_wait = "3s"
iso_name = "ubuntu-20.04.2-live-server-amd64.iso"
iso_checksum = "d1f2bf834bbe9bb43faf16f9be992a6f3935e65be0edece1dee2aa6eb1767423"
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