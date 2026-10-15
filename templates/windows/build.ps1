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
        'win11-24h2-enterprise',
        'win11-25h2-enterprise',
        'win11-26h2-enterprise'
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

  # Configure patched Hyper-V plugin
  $patchedPluginPath = Resolve-Path "..\..\tools\plugins"
  $env:PACKER_PLUGIN_PATH = $patchedPluginPath.Path
  
  Write-Host "Using patched Hyper-V plugin from: $env:PACKER_PLUGIN_PATH"

  ..\..\tools\packer.exe init  windows.pkr.hcl
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=target_path="${isoFolder}" -var=vm_overrides_path="${overridesFile}" gen-files.pkr.hcl
  if ($LASTEXITCODE -ne 0) { throw "gen-files packer build failed (exit $LASTEXITCODE)" }
  ..\..\tools\oscdimg.exe -u2 "${isoFolder}" "..\..\builds\$buildid.iso"
  if ($LASTEXITCODE -ne 0) { throw "oscdimg failed (exit $LASTEXITCODE)" }
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=secondary_iso_path="..\..\builds\$buildid.iso" -var=hyperv_switch="${SwitchName}" windows.pkr.hcl
  if ($LASTEXITCODE -ne 0) { throw "windows packer build failed (exit $LASTEXITCODE)" }
  $metadataJson | Set-Content -Path ..\..\builds\$template_name-stage0\metadata.json
  Copy-Item $overridesFile ..\..\builds\$template_name-stage0\vm-overrides.json
}
finally{
  # Best-effort cleanup of the transient Autounattend ISO and its source folder.
  # These are disposable once the VM build has consumed the .iso, so a missing
  # path here must never mask a successful build (or the real build error).
  if (Test-Path $isoFolder) { Remove-Item -Recurse -Force $isoFolder -ErrorAction SilentlyContinue }
  if (Test-Path "..\..\builds\$buildid.iso") { Remove-Item "..\..\builds\$buildid.iso" -Force -ErrorAction SilentlyContinue }
  Pop-Location

}
