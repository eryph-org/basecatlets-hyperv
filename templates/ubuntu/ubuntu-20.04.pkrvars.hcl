
template = "ubuntu-20.04"
mirror_directory = "20.04"
boot_wait = "2s"
iso_name = "ubuntu-20.04.6-live-server-amd64.iso"
iso_checksum = "sha256:b8f31413336b9393ad5d8ef0282717b2ab19f007df2e9ed5196c13d8f9153c8b"
boot_cmds = [
    " <wait10>",
    "c", 
    "<wait>", 
    "set gfxpayload=keep", 
    "<enter><wait5>", 
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