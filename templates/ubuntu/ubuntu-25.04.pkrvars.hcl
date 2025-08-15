template = "ubuntu-25.04"
mirror_directory = "25.04"
boot_wait = "3s"
iso_name = "ubuntu-25.04-live-server-amd64.iso"
iso_checksum = "sha256:8B44046211118639C673335A80359F4B3F0D9E52C33FE61C59072B1B61BDECC5"
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