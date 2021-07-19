param(
      [Parameter(Mandatory=$true, Position=0)]
      [ValidateSet(
        'ubuntu-20.04',
        'ubuntu-21.04'
      )]
      [string]$Template_name,
      [string]$SwitchName,
      [switch]$VagrantBox = $false)

$ErrorActionPreference = 'Stop'

if([string]::IsNullOrWhiteSpace($SwitchName)){
  $SwitchName = (Get-VMSwitch -SwitchType External | Select-Object -First 1).Name
}

if([string]::IsNullOrWhiteSpace($SwitchName)){
  throw 'Switch name not set and no external switch found'
}


Push-Location $PSScriptRoot

try{
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=hyperv_switch="${SwitchName}" ubuntu-autoinstall.pkr.hcl  
}
finally{
  Pop-Location

}
