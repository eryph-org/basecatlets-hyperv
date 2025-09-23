#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$BuildDir = "../../builds"
)

$ErrorActionPreference = "Stop"

# Validate environment
if (-not (Get-Command egs-tool -ErrorAction SilentlyContinue)) {
    throw "egs-tool is required but not found in PATH. Ensure eryph guest services are installed."
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw "SSH is required but not found in PATH"
}

$ScriptDir = $PSScriptRoot
$OutputDir = Resolve-Path $BuildDir
$UploadDir = "$ScriptDir\azure-linux-build"

$catletConfig = @"
name: azure-linux-build
parent: dbosoft/ubuntu-22.04

fodder: 
  - name: azure-linux-build
    type: shellscript
    content: |
        #!/bin/bash
        cd /
        apt-get update
        apt-get install -y git make rpm
        git clone https://github.com/microsoft/azurelinux.git
        cd azurelinux
        git checkout 3.0-stable

"@
$booted = $false
$catlets = Get-Catlet | Where-Object { $_.Name -eq "azure-linux-build" }
if ($catlets.Count -eq 0) {
    Write-Host "Creating build catlet..." -ForegroundColor Cyan
    $catlet = $catletConfig | New-Catlet | Out-Null
    Write-Host "Build catlet created successfully" -ForegroundColor Green
    $booted = $true
} else {
    Write-Host "Build catlet already exists" -ForegroundColor Yellow
    if ($catlets.Count -gt 1) {
        Write-Error "Multiple catlets found with the same name."
        exit 1
    }

    $catlet = $catlets
}

$catlet = Get-Catlet | Where-Object { $_.Name -eq "azure-linux-build" }

if ($catlet.Status -ne "Running") {
    Write-Host "Starting build catlet..." -ForegroundColor Cyan
    $catlet | Start-Catlet -Force
    Write-Host "Build catlet started successfully" -ForegroundColor Green
}

$VmId = $catlet.VmId

egs-tool add-ssh-config $VmId
$Alias = "$VmId.hyper-v.alt"

# wait for egs to be ready
while ($true) {
    # egs-tools get-status $VmId
    $status = egs-tool get-status $VmId
    if ($status -eq "available") {
        break
    }
    Start-Sleep -Seconds 5
    Write-Host "Waiting for VM to be available..." -ForegroundColor Yellow
}

# login via ssh and check if cloud-init is done
Write-Host "Waiting for cloud-init to complete..." -ForegroundColor Cyan
ssh $Alias -C "cloud-init status --wait"

# check status
$status = & ssh $Alias -C "cloud-init status"
if ($status -ne "status: done") {
    & ssh $Alias -C "cloud-init status --long"
    & ssh $Alias -C "cat /var/log/cloud-init.log"
    exit 1
}

if($booted) {
    Write-Host "Installing prerequisites..." -ForegroundColor Green

    & ssh $Alias -C "sudo make -C /azurelinux/toolkit install-prereqs-and-configure"
}


# Upload our build files
Write-Host "Uploading build files..." -ForegroundColor Cyan
egs-tool upload-directory $VmId "$ScriptDir\scripts" /azurelinux/azure-linux-build/scripts --Recursive --Overwrite
egs-tool upload-directory $VmId "$ScriptDir\imageconfigs" /azurelinux/azure-linux-build/imageconfigs --Recursive --Overwrite
egs-tool upload-directory $VmId "$ScriptDir\packagelists" /azurelinux/azure-linux-build/packagelists --Recursive --Overwrite

Write-Host "Building eryph guest services RPM..." -ForegroundColor Cyan
& ssh $Alias -C "chmod +x ~/azure-linux-build/scripts/build-eryph-rpm.sh"
& ssh $Alias -C "~/azure-linux-build/scripts/build-eryph-rpm.sh"

# Copy our configuration files to the toolkit
Write-Host "Copying eryph configuration to Azure Linux toolkit..." -ForegroundColor Cyan
& ssh $Alias -C "cp ~/azure-linux-build/imageconfigs/eryph-core-efi.json ~/azurelinux/toolkit/imageconfigs/"
& ssh $Alias -C "cp -r ~/azure-linux-build/scripts ~/azurelinux/toolkit/imageconfigs/postinstallscripts/"
& ssh $Alias -C "cp -r ~/azure-linux-build/packagelists ~/azurelinux/toolkit/"

Write-Host "Build files uploaded and RPM built successfully" -ForegroundColor Green

# Build the image
Write-Host "`nBuilding Azure Linux image..." -ForegroundColor Cyan
Write-Host "This may take 30-60 minutes depending on hardware..." -ForegroundColor Yellow

& ssh $Alias -C "sudo make -C /azurelinux/toolkit image REBUILD_TOOLS=y REBUILD_PACKAGES=n CONFIG_FILE=./imageconfigs/eryph-core-efi.json"
 

