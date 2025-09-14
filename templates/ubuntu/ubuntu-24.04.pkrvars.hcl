template = "ubuntu-24.04"
mirror_directory = "24.04"
boot_wait = "3s"
iso_name = "ubuntu-24.04.3-live-server-amd64.iso"
iso_checksum = "sha256:C3514BF0056180D09376462A7A1B4F213C1D6E8EA67FAE5C25099C6FD3D8274B"
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