# hyperv-boxes
Vagrant boxes for eryph and Hyper-V

This repository contains packer templates to build boxes for Hyper-V that are optimized for erpyh:

- cloud-init (cloubase-init for Windows) enabled
- hyper-v gen 2 with UEFI secure boot enabled
- naming conventions for eryph VMs


## Building Ubuntu boxes

Generic Hyper-V / eryph

``` cmd
cd templates\ubuntu
..\..\tools\packer.exe build -var-file="ubuntu-20.04.pkrvars.hcl"  \ 
-var-file=..\linux\vagrant.pkrvars.hcl  -var hyperv_switch=<SwitchName>
```

Vagrant boxes

``` cmd
cd templates\ubuntu
..\..\tools\packer.exe build -var-file="ubuntu-20.04.pkrvars.hcl"  \ 
-var hyperv_switch=<SwitchName>
```


## Building Windows images

To build Windows images you have to run the build.ps1 script in folder templates\windows.
