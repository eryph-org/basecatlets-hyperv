param(
      [Parameter(Mandatory=$true, Position=0)]
      [ValidateSet(
        'ubuntu-20.04',
        'ubuntu-22.04',
        'ubuntu-24.04',
        'ubuntu-25.04'
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

$metadata = @{
  "_os_type" = "linux"
  "_os_name"  = $Template_name
  build_date = (Get-Date).ToString("s")
}

$metadataJson = $metadata | ConvertTo-Json
$overridesFile = New-TemporaryFile
Push-Location $PSScriptRoot

try{
  # Configure patched Hyper-V plugin
  $patchedPluginPath = Resolve-Path "..\..\tools\plugins"
  $env:PACKER_PLUGIN_PATH = $patchedPluginPath.Path
  
  # Clear any cached plugins that might conflict
  $env:PACKER_CACHE_DIR = Join-Path $env:TEMP "packer_cache_build_$template_name"
  if (Test-Path $env:PACKER_CACHE_DIR) {
      Remove-Item -Path $env:PACKER_CACHE_DIR -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Path $env:PACKER_CACHE_DIR -Force | Out-Null
  
  Write-Host "Using patched Hyper-V plugin from: $env:PACKER_PLUGIN_PATH"

  ..\..\tools\packer.exe init .\ubuntu-autoinstall.pkr.hcl
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=vm_overrides_path="${overridesFile}" gen-files.pkr.hcl
  ..\..\tools\packer.exe build -var-file="${template_name}.pkrvars.hcl" -var=hyperv_switch="${SwitchName}" ubuntu-autoinstall.pkr.hcl  
  $metadataJson | sc -Path ..\..\builds\$template_name-stage0\metadata.json
  Copy-Item $overridesFile ..\..\builds\$template_name-stage0\vm-overrides.json
}
finally{
  Pop-Location

}
