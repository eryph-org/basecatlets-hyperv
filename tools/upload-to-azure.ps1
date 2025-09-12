[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$BuildPath,  # Path to build directory containing VHDX
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,  # Azure resource group
    
    [Parameter(Mandatory=$true)]
    [string]$Location,  # Azure region
    
    [Parameter(Mandatory=$true)]
    [string]$ImageName,  # Name for Azure managed image
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('windows', 'ubuntu', 'linux')]
    [string]$OSType,  # Operating system type
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Premium_LRS', 'Standard_LRS', 'StandardSSD_LRS', 'UltraSSD_LRS', 'Premium_ZRS', 'StandardSSD_ZRS')]
    [string]$StorageType = 'Premium_LRS',  # Azure disk storage type
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,  # Azure subscription ID
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipImageCreation  # Only upload VHD, don't create managed image
)

$ErrorActionPreference = 'Stop'

Write-Host "==========================================="
Write-Host "Azure VHD Upload and Image Creation"
Write-Host "==========================================="
Write-Host "Build Path: $BuildPath"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"
Write-Host "Image Name: $ImageName"
Write-Host "OS Type: $OSType"
Write-Host "Storage Type: $StorageType"
Write-Host ""

# Check if Azure PowerShell is available
try {
    $null = Get-Module -Name Az.Accounts -ListAvailable
    $null = Get-Module -Name Az.Compute -ListAvailable
    $null = Get-Module -Name Az.Storage -ListAvailable
} catch {
    throw "Azure PowerShell modules (Az.Accounts, Az.Compute, Az.Storage) are required. Please install them with: Install-Module -Name Az"
}

# Test Azure credentials at the beginning
Write-Host "Testing Azure credentials..."
try {
    # Verify we're logged in to Azure
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in to Azure"
    }
    
    # Set Azure context if subscription ID is provided
    if ($SubscriptionId) {
        Write-Host "Setting Azure subscription context to: $SubscriptionId"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $context = Get-AzContext
    }
    
    Write-Host "Using Azure subscription: $($context.Subscription.Name)"
    
    # Test if we can actually make Azure calls by trying to list resource groups
    $null = Get-AzResourceGroup -ErrorAction Stop | Select-Object -First 1
    Write-Host "Azure credentials verified successfully"
    
} catch {
    throw "Azure credentials test failed. Please login to Azure using Connect-AzAccount: $_"
}

# Find VHD or VHDX files in the build directory
$vhdDir = Join-Path $BuildPath "Virtual Hard Disks"
if (-not (Test-Path $vhdDir)) {
    throw "Virtual Hard Disks directory not found in build path: $vhdDir"
}

# Look for VHD files first (already converted), then VHDX
$vhdFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhd"
$vhdxFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhdx"

if ($vhdFiles.Count -gt 0) {
    $sourcePath = $vhdFiles[0].FullName
    $alreadyVhd = $true
    Write-Host "Found VHD: $sourcePath (already in VHD format)"
} elseif ($vhdxFiles.Count -gt 0) {
    $sourcePath = $vhdxFiles[0].FullName
    $alreadyVhd = $false
    Write-Host "Found VHDX: $sourcePath"
} else {
    throw "No VHD or VHDX files found in: $vhdDir"
}

# Convert VHDX to fixed VHD for Azure compatibility if needed
if ($alreadyVhd) {
    $vhdPath = $sourcePath
    Write-Host "`nUsing existing VHD file (skipping conversion)"
} else {
    $vhdPath = [System.IO.Path]::ChangeExtension($sourcePath, '.vhd')
    Write-Host "`nConverting VHDX to fixed VHD format..."
    Write-Host "Source: $sourcePath"
    Write-Host "Target: $vhdPath"
    
    try {
        Convert-VHD -Path $sourcePath -DestinationPath $vhdPath -VHDType Fixed
        Write-Host "VHD conversion completed successfully"
    } catch {
        throw "Failed to convert VHDX to VHD: $_"
    }
}

# Verify and align VHD size to 1MB boundary (Azure requirement)
$vhd = Get-VHD -Path $vhdPath
$currentSize = $vhd.Size
$alignedSize = [Math]::Ceiling($currentSize / 1MB) * 1MB

if ($currentSize -ne $alignedSize) {
    Write-Host "Resizing VHD to align with 1MB boundary..."
    Write-Host "Current size: $currentSize bytes"
    Write-Host "Aligned size: $alignedSize bytes"
    Resize-VHD -Path $vhdPath -SizeBytes $alignedSize
}

$finalVhd = Get-VHD -Path $vhdPath
Write-Host "Final VHD size: $($finalVhd.Size) bytes ($([Math]::Round($finalVhd.Size / 1GB, 2)) GB)"

# Verify Azure resource group exists
try {
    $null = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
    Write-Host "`nUsing existing resource group: $ResourceGroup"
} catch {
    throw "Resource group '$ResourceGroup' not found. Please create it first or specify an existing resource group."
}

# Generate unique names for Azure resources
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$diskName = "$ImageName-disk-$timestamp"
$diskSizeGB = [Math]::Ceiling($finalVhd.Size / 1GB)

# Determine Azure OS type
$azureOsType = if ($OSType -eq 'windows') { 'Windows' } else { 'Linux' }

Write-Host "`nCreating empty managed disk for upload..."
Write-Host "Disk name: $diskName"
Write-Host "Disk size: $diskSizeGB GB"
Write-Host "OS type: $azureOsType"

# Create empty managed disk configured for upload
$diskConfig = New-AzDiskConfig `
    -Location $Location `
    -DiskSizeGB $diskSizeGB `
    -AccountType $StorageType `
    -OsType $azureOsType `
    -HyperVGeneration 'V2' `
    -CreateOption 'Upload'

try {
    $disk = New-AzDisk `
        -ResourceGroupName $ResourceGroup `
        -DiskName $diskName `
        -Disk $diskConfig
    
    Write-Host "Empty managed disk created successfully"
} catch {
    throw "Failed to create managed disk: $_"
}

try {
    # Grant access for upload (24 hours should be more than enough)
    Write-Host "`nGranting write access to managed disk..."
    $diskAccess = Grant-AzDiskAccess `
        -ResourceGroupName $ResourceGroup `
        -DiskName $diskName `
        -DurationInSecond 86400 `
        -Access 'Write'
    
    Write-Host "Upload SAS URL obtained"
    
    # Upload VHD using Add-AzVhd (this handles the upload protocol efficiently)
    Write-Host "`nUploading VHD to Azure..."
    Write-Host "This may take a while depending on VHD size and connection speed..."
    
    $uploadJob = Add-AzVhd `
        -ResourceGroupName $ResourceGroup `
        -Destination $diskAccess.AccessSAS `
        -LocalFilePath $vhdPath `
        -NumberOfUploaderThreads 8
    
    Write-Host "VHD upload completed successfully"
    
    # Revoke access to the disk
    Write-Host "`nRevoking disk access..."
    Revoke-AzDiskAccess `
        -ResourceGroupName $ResourceGroup `
        -DiskName $diskName | Out-Null
    
    Write-Host "Disk access revoked"
    
    if (-not $SkipImageCreation) {
        # Create managed image from the uploaded disk
        Write-Host "`nCreating managed image..."
        Write-Host "Image name: $ImageName"
        
        $imageConfig = New-AzImageConfig `
            -Location $Location `
            -HyperVGeneration 'V2'
        
        $imageConfig = Set-AzImageOsDisk `
            -Image $imageConfig `
            -OsType $azureOsType `
            -OsState 'Generalized' `
            -ManagedDiskId $disk.Id
        
        $image = New-AzImage `
            -ResourceGroupName $ResourceGroup `
            -ImageName $ImageName `
            -Image $imageConfig
        
        Write-Host "Managed image created successfully"
        
        # Clean up the temporary disk (image now contains a copy)
        Write-Host "`nCleaning up temporary disk..."
        Remove-AzDisk `
            -ResourceGroupName $ResourceGroup `
            -DiskName $diskName `
            -Force | Out-Null
        
        Write-Host "Temporary disk cleanup completed"
    }
    
} catch {
    # Clean up on failure
    Write-Host "Upload failed, cleaning up resources..."
    
    try {
        Revoke-AzDiskAccess -ResourceGroupName $ResourceGroup -DiskName $diskName -ErrorAction SilentlyContinue | Out-Null
        Remove-AzDisk -ResourceGroupName $ResourceGroup -DiskName $diskName -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-Warning "Failed to clean up temporary disk: $diskName"
    }
    
    throw "Azure upload failed: $_"
    
} finally {
    # Clean up local VHD file (only if we converted from VHDX)
    if (-not $alreadyVhd -and (Test-Path $vhdPath)) {
        Write-Host "`nCleaning up converted VHD file..."
        Remove-Item -Path $vhdPath -Force
    }
}

Write-Host "`n==========================================="
Write-Host "Azure upload completed successfully!"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"

if (-not $SkipImageCreation) {
    Write-Host "Managed Image: $ImageName"
    Write-Host ""
    Write-Host "You can now create VMs from this image using:"
    Write-Host "az vm create --resource-group $ResourceGroup --name MyVM --image $ImageName --admin-username azureuser"
} else {
    Write-Host "Managed Disk: $diskName"
    Write-Host ""
    Write-Host "You can now create an image or VM from this disk"
}
Write-Host "==========================================="

exit 0