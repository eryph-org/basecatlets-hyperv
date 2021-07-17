# hyperv-boxes
Vagrant boxes for Hyper-v


## Building Ubuntu images

Generic Hyper-V

``` cmd
cd templates\ubuntu
..\..\packer.exe build -var-file=ubuntu-20.04.pkrvars.hcl  \ 
-var-file=..\linux\vagrant.pkrvars.hcl  -var hyperv_switch=<SwitchName>
```


Vagrant Box

``` cmd
cd templates\ubuntu
..\..\packer.exe build -var-file=ubuntu-20.04.pkrvars.hcl  \ 
-var hyperv_switch=<SwitchName>
```