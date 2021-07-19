param(
      [Parameter(Mandatory=$true, Position=0)]
      [ValidateSet(
        'winsrv2012r2-standard',
        'winsrv2012r2-standardcore',
        'winsrv2016-standard',
        'winsrv2016-standardcore',
        'winsrv2019-standard',
        'winsrv2019-standardcore',
        'win10-2004-enterprise'
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
$buildid = New-Guid
$isoFolder = "..\..\builds\iso-${buildid}"

try{
  mkdir $isoFolder | Out-Null

  ..\..\tools\packer.exe init  windows.pkr.hcl
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=target_path="${isoFolder}" gen-files.pkr.hcl
  ..\..\tools\oscdimg.exe -u2 "${isoFolder}" "..\..\builds\$buildid.iso"
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=secondary_iso_path="..\..\builds\$buildid.iso" -var=hyperv_switch="${SwitchName}" windows.pkr.hcl

}
finally{
  Remove-Item -Recurse $isoFolder
  Remove-Item "..\..\builds\$buildid.iso"
  Pop-Location

}
