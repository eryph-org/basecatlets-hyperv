[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

try {
    Write-Host "Installing patched packer-plugin-hyperv with TPM fix..." -ForegroundColor Cyan
    
    # Check if the fixed plugin exists
    $fixedPlugin = Join-Path $PSScriptRoot "plugin-dev\packer-plugin-hyperv-fixed.exe"
    if (!(Test-Path $fixedPlugin)) {
        throw "Fixed plugin not found at: $fixedPlugin. Please build it first with: cd plugin-dev; go build -o packer-plugin-hyperv-fixed.exe ."
    }
    
    # Get file info for verification
    $pluginInfo = Get-Item $fixedPlugin
    Write-Host "Using plugin: Size=$($pluginInfo.Length) bytes, Modified=$($pluginInfo.LastWriteTime)"
    
    # Use packer plugins install to properly install the plugin
    # Packer will handle the naming, placement, and checksum creation
    Write-Host "`nInstalling plugin with Packer..." -ForegroundColor Yellow
    & .\tools\packer.exe plugins install --path $fixedPlugin "github.com/hashicorp/hyperv"
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install plugin with Packer"
    }
    
    Write-Host "`nPatched plugin installed successfully!" -ForegroundColor Green
    Write-Host "The plugin will be used automatically by Packer for hyperv-vmcx builders."
    Write-Host "`nInstalled plugins:"
    & .\tools\packer.exe plugins installed | Select-String hyperv
    
} catch {
    Write-Error "Installation failed: $_"
    exit 1
} finally {
    Pop-Location
}