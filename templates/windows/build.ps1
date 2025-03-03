param(
      [Parameter(Mandatory=$true, Position=0)]
      [ValidateSet(
        'winsrv2012r2-standard',
        'winsrv2012r2-standardcore',
        'winsrv2016-standard',
        'winsrv2016-standardcore',
        'winsrv2019-standard',
        'winsrv2019-standardcore',
        'winsrv2022-standard',
        'winsrv2022-standardcore',
        'winsrv2022-datacenter',
        'winsrv2025-standard',
        'winsrv2025-standardcore',
        'winsrv2025-datacenter',
        'win10-2004-enterprise',
        'win10-20h2-enterprise',
        'win11-21h1-enterprise',
        'win11-22h2-enterprise',
        'win11-24h2-enterprise'
      )]
      [string]$Template_name,
      [string]$SwitchName)

$ErrorActionPreference = 'Stop'

if([string]::IsNullOrWhiteSpace($SwitchName)){
   $SwitchName = (Get-VMSwitch -SwitchType External | Select-Object -First 1).Name
}

if([string]::IsNullOrWhiteSpace($SwitchName)){
 throw 'Switch name not set and no external switch found'
}

# translate template name to os name and edition
$osNameParts = $Template_name -split '-'

if($osNameParts[0].StartsWith('winsrv')){
  $splitVersion = $osNameParts[0] -split 'winsrv'
  $osName = "Windows Server " + $splitVersion[1]

}else {
  $splitVersion = $osNameParts[0] -split 'win'
  $osName = "Windows " + $splitVersion[1]
}

$TextInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo

if($osNameParts.Length -gt 2)
{
  $editionName = $TextInfo.ToTitleCase($osNameParts[2])
  $osEdition = $osNameParts[1] + " " + $editionName
}else{
  $osEdition = $TextInfo.ToTitleCase($osNameParts[1])
}

Write-Host "Building $osName (Edition: $osEdition)"

$metadata = @{
    "_os_type" = "windows"
    "_os_name"  = $osName
    "os_edition" = $osEdition
    build_date = (Get-Date).ToString("s")
}

$metadataJson = $metadata | ConvertTo-Json

Push-Location $PSScriptRoot
$buildid = New-Guid
$isoFolder = "..\..\builds\iso-${buildid}"

$overridesFile = New-TemporaryFile

try{
  mkdir $isoFolder | Out-Null

  ..\..\tools\packer.exe init  windows.pkr.hcl
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=target_path="${isoFolder}" -var=vm_overrides_path="${overridesFile}" gen-files.pkr.hcl
  ..\..\tools\oscdimg.exe -u2 "${isoFolder}" "..\..\builds\$buildid.iso"
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=secondary_iso_path="..\..\builds\$buildid.iso" -var=hyperv_switch="${SwitchName}" windows.pkr.hcl
  $metadataJson | Set-Content -Path ..\..\builds\$template_name-stage0\metadata.json
  Copy-Item $overridesFile ..\..\builds\$template_name-stage0\vm-overrides.json
}
finally{
  Remove-Item -Recurse $isoFolder
  Remove-Item "..\..\builds\$buildid.iso"
  Pop-Location

}
