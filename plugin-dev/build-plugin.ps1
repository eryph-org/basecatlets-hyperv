[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

# Verify Go is installed
$goExe = if (Get-Command go -ErrorAction SilentlyContinue) {
    "go"
} elseif (Test-Path "C:\Program Files\Go\bin\go.exe") {
    "C:\Program Files\Go\bin\go.exe"
} else {
    Write-Error "Go is not installed. Please install Go using: choco install golang -y"
    exit 1
}

try {
    Write-Host "Building patched packer-plugin-hyperv with TPM fix..." -ForegroundColor Cyan
    
    $goVersion = & $goExe version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get Go version"
    }
    Write-Host "Go version: $goVersion"
    
    # Check if repository exists, clone if not
    if (!(Test-Path "packer-plugin-hyperv")) {
        Write-Host "`nCloning packer-plugin-hyperv repository..." -ForegroundColor Yellow
        git clone https://github.com/hashicorp/packer-plugin-hyperv.git
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone repository"
        }
    }
    
    Push-Location "packer-plugin-hyperv"
    
    try {
        # Add PR #137 remote if not exists
        $remotes = git remote
        if ($remotes -notcontains "pr137") {
            Write-Host "Adding PR #137 remote..." -ForegroundColor Yellow
            git remote add pr137 https://github.com/bdonaldson77/packer-plugin-hyperv.git
            git fetch pr137
        }
        
        # Checkout PR #137 branch (has initial TPM fix in hyperv.go)
        Write-Host "`nChecking out PR #137 branch with initial TPM fix..." -ForegroundColor Yellow
        git checkout -f pr137/fix/tpm-secureboottemplate-skip
        git clean -fd
        
        # Apply our additional fix for step_clone_vm.go
        Write-Host "`nApplying additional fix to skip secure boot config for cloned VMs..." -ForegroundColor Yellow
        git apply ../additional_tpm_fix.patch
        if ($LASTEXITCODE -ne 0) {
            # If patch fails, try the old patch name for backwards compatibility
            if (Test-Path ../step_clone_vm.patch) {
                Write-Host "Trying legacy patch file..." -ForegroundColor Yellow
                git apply ../step_clone_vm.patch
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to apply patch. Ensure additional_tpm_fix.patch exists in plugin-dev directory"
            }
        }
        Write-Host "Patch applied successfully" -ForegroundColor Green
        
        # Build the plugin
        Write-Host "`nBuilding plugin..." -ForegroundColor Yellow
        & $goExe build -o ../packer-plugin-hyperv-fixed.exe .
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build plugin"
        }
        
        Write-Host "`nBuild successful!" -ForegroundColor Green
        
        # Get file info
        $pluginInfo = Get-Item ../packer-plugin-hyperv-fixed.exe
        Write-Host "Plugin built: $($pluginInfo.Name)"
        Write-Host "Size: $($pluginInfo.Length) bytes"
        Write-Host "Location: $($pluginInfo.FullName)"
        
    } finally {
        Pop-Location
    }
    
    Write-Host "`n===========================================" -ForegroundColor Cyan
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "This plugin includes:" -ForegroundColor Cyan
    Write-Host "  1. PR #137: Check TPM before modifying SecureBootTemplate (hyperv.go)"
    Write-Host "  2. Additional fix: Skip secure boot config entirely for cloned VMs (step_clone_vm.go)"
    Write-Host ""
    Write-Host "Next step: Run .\install-patched-plugin.ps1 to install the plugin" -ForegroundColor Yellow
    Write-Host "===========================================" -ForegroundColor Cyan
    
} catch {
    Write-Error "Build failed: $_"
    exit 1
} finally {
    Pop-Location
}