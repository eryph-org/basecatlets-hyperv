[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

try {
    Write-Host "Installing patched packer-plugin-hyperv with TPM fix..." -ForegroundColor Cyan

    # Check if the fixed plugin exists, if not build it
    $fixedPlugin = Join-Path $PSScriptRoot "plugin-dev\packer-plugin-hyperv-fixed.exe"
    if (!(Test-Path $fixedPlugin)) {
        Write-Host "Fixed plugin not found, building from source..." -ForegroundColor Yellow

        # Change to plugin-dev directory and build
        Push-Location (Join-Path $PSScriptRoot "plugin-dev")
        try {
            Write-Host "Applying patches and building packer-plugin-hyperv..." -ForegroundColor Yellow

            # Apply patches if they exist
            $patchesDir = Join-Path $PSScriptRoot "patches"
            if (Test-Path $patchesDir) {
                $patches = Get-ChildItem -Path $patchesDir -Filter "*.patch" | Sort-Object Name
                foreach ($patch in $patches) {
                    Write-Host "Applying patch: $($patch.Name)" -ForegroundColor Yellow
                    & git apply --ignore-whitespace $patch.FullName
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Failed to apply patch $($patch.Name), continuing anyway..."
                    }
                }
            }

            & go build -o packer-plugin-hyperv-fixed.exe .

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to build plugin with Go"
            }

            Write-Host "Plugin built successfully with patches applied!" -ForegroundColor Green
        } finally {
            Pop-Location
        }
    }
    
    # Get file info for verification
    $pluginInfo = Get-Item $fixedPlugin
    Write-Host "Using plugin: Size=$($pluginInfo.Length) bytes, Modified=$($pluginInfo.LastWriteTime)"

    # Uninstall any existing hyperv plugins to avoid conflicts
    Write-Host "`nUninstalling existing hyperv plugins..." -ForegroundColor Yellow
    $existingPlugins = & .\tools\packer.exe plugins installed | Select-String "github.com\\hashicorp\\hyperv"
    if ($existingPlugins) {
        Write-Host "Found existing plugins:"
        $existingPlugins | ForEach-Object { Write-Host "  - $_" }

        # Remove existing plugin installations
        & .\tools\packer.exe plugins remove "github.com/hashicorp/hyperv" 2>$null
        Write-Host "Existing plugins removed."
    } else {
        Write-Host "No existing hyperv plugins found."
    }

    # Use packer plugins install to properly install the plugin
    # Packer will handle the naming, placement, and checksum creation
    Write-Host "`nInstalling patched plugin with Packer..." -ForegroundColor Yellow
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