[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$ExportPath,  # Path to Hyper-V VM export directory
    
    [Parameter(Mandatory=$false)]
    [switch]$Force  # Skip confirmation prompts
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================="
Write-Host "Prepare VM Export for Repacking"
Write-Host "========================================="
Write-Host "Export Path: $ExportPath"
Write-Host ""

# Validate export path structure
$vmDir = Join-Path $ExportPath "Virtual Machines"
$vhdDir = Join-Path $ExportPath "Virtual Hard Disks"

if (-not (Test-Path $vmDir)) {
    throw "Invalid export path. 'Virtual Machines' directory not found."
}

if (-not (Test-Path $vhdDir)) {
    throw "Invalid export path. 'Virtual Hard Disks' directory not found."
}

# Find the VMCX file
$vmcxFile = Get-ChildItem -Path $vmDir -Filter "*.vmcx" | Select-Object -First 1
if (-not $vmcxFile) {
    throw "No .vmcx file found in export path."
}

Write-Host "Found VM configuration: $($vmcxFile.Name)"

# Generate a unique VM name for import
$tempVMName = "TempRepack_$(Get-Random -Maximum 99999)"
Write-Host "Temporary VM name: $tempVMName"
Write-Host ""

# Import the VM without moving files (register in-place)
Write-Host "Importing VM for disk consolidation..."
try {
    $vm = Import-VM -Path $vmcxFile.FullName `
                    -Copy `
                    -GenerateNewId `
                    -VirtualMachinePath $ExportPath `
                    -VhdDestinationPath $vhdDir `
                    -SnapshotFilePath $ExportPath `
                    -SmartPagingFilePath $ExportPath
    
    # Rename to temp name to avoid conflicts
    Rename-VM -VM $vm -NewName $tempVMName
    
    Write-Host "  [OK] VM imported successfully"
} catch {
    throw "Failed to import VM: $_"
}

# Check for checkpoints/snapshots
$checkpoints = Get-VMSnapshot -VM $vm
if ($checkpoints) {
    Write-Host ""
    Write-Host "Checkpoints detected: $($checkpoints.Count)"
    
    if (-not $Force) {
        $response = Read-Host "Do you want to merge all checkpoints? (Y/N)"
        if ($response -ne 'Y') {
            Write-Host "Aborting. Cleaning up..."
            Remove-VM -VM $vm -Force
            exit 1
        }
    }
    
    # Remove all checkpoints (this merges them)
    Write-Host "Merging checkpoints..."
    foreach ($checkpoint in $checkpoints) {
        Write-Host "  Removing checkpoint: $($checkpoint.Name)"
        Remove-VMSnapshot -VMSnapshot $checkpoint
    }
    
    Write-Host "  [OK] All checkpoints merged"
}

# Get all hard drives
$hardDrives = Get-VMHardDiskDrive -VM $vm
Write-Host ""
Write-Host "Processing $($hardDrives.Count) disk(s)..."

foreach ($hdd in $hardDrives) {
    $vhdPath = $hdd.Path
    $vhdName = Split-Path $vhdPath -Leaf
    
    Write-Host "  Checking: $vhdName"
    
    # Check if it's a differencing disk
    $vhd = Get-VHD -Path $vhdPath
    
    if ($vhd.ParentPath) {
        Write-Host "    [!] Differencing disk detected"
        Write-Host "    Parent: $(Split-Path $vhd.ParentPath -Leaf)"
        
        # Create a new consolidated disk
        $newPath = Join-Path $vhdDir "$([System.IO.Path]::GetFileNameWithoutExtension($vhdName))_merged.vhdx"
        
        Write-Host "    Merging to new disk..."
        
        # Convert to a new disk (this merges the chain)
        Convert-VHD -Path $vhdPath -DestinationPath $newPath -VHDType Dynamic
        
        # Replace the disk in the VM
        Remove-VMHardDiskDrive -VMHardDiskDrive $hdd
        Add-VMHardDiskDrive -VM $vm `
                            -ControllerType $hdd.ControllerType `
                            -ControllerNumber $hdd.ControllerNumber `
                            -ControllerLocation $hdd.ControllerLocation `
                            -Path $newPath
        
        # Remove old differencing disk and parent if not used elsewhere
        $parentPath = $vhd.ParentPath
        Remove-Item -Path $vhdPath -Force
        
        # Check if parent is used by other disks
        $otherDisks = Get-ChildItem -Path $vhdDir -Filter "*.vhd*" | 
                      Where-Object { $_.FullName -ne $vhdPath } |
                      ForEach-Object { Get-VHD -Path $_.FullName -ErrorAction SilentlyContinue } |
                      Where-Object { $_.ParentPath -eq $parentPath }
        
        if (-not $otherDisks) {
            Write-Host "    Removing unused parent disk..."
            Remove-Item -Path $parentPath -Force
        }
        
        # Rename merged disk back to original name
        Move-Item -Path $newPath -Destination $vhdPath -Force
        
        # Update VM to use the renamed disk
        Remove-VMHardDiskDrive -VMHardDiskDrive (Get-VMHardDiskDrive -VM $vm | Where-Object { $_.Path -eq $newPath })
        Add-VMHardDiskDrive -VM $vm `
                            -ControllerType $hdd.ControllerType `
                            -ControllerNumber $hdd.ControllerNumber `
                            -ControllerLocation $hdd.ControllerLocation `
                            -Path $vhdPath
        
        Write-Host "    [OK] Disk consolidated"
    } else {
        Write-Host "    [OK] Standalone disk (no merge needed)"
    }
}

# Export the VM again with consolidated disks
Write-Host ""
Write-Host "Re-exporting VM with consolidated disks..."

$exportTempPath = Join-Path $env:TEMP "VMExportTemp_$(Get-Random)"
New-Item -ItemType Directory -Path $exportTempPath -Force | Out-Null

try {
    Export-VM -VM $vm -Path $exportTempPath
    
    # Get the exported VM folder
    $exportedFolder = Get-ChildItem -Path $exportTempPath -Directory | Select-Object -First 1
    
    # Clean the original export directory
    Write-Host "Updating original export..."
    Remove-Item -Path "$ExportPath\*" -Recurse -Force
    
    # Move the new export to the original location
    Get-ChildItem -Path $exportedFolder.FullName | Move-Item -Destination $ExportPath -Force
    
    Write-Host "  [OK] Export updated with consolidated disks"
    
} finally {
    # Clean up temp export
    if (Test-Path $exportTempPath) {
        Remove-Item -Path $exportTempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove the temporary VM
Write-Host "Cleaning up temporary VM..."
Remove-VM -VM $vm -Force

Write-Host ""
Write-Host "========================================="
Write-Host "[OK] Export prepared successfully!"
Write-Host "All differencing disks have been consolidated."
Write-Host "The export is now ready for repacking."
Write-Host "========================================="