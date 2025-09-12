[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$ExportPath,  # Path to Hyper-V VM export directory
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf  # Preview changes without executing
)

$ErrorActionPreference = 'Stop'

function Get-VHDXChain {
    param(
        [string]$VHDXPath
    )
    
    $chain = @()
    $currentVHDX = $VHDXPath
    
    while ($currentVHDX) {
        if (-not (Test-Path $currentVHDX)) {
            throw "VHDX file not found: $currentVHDX"
        }
        
        $chain += $currentVHDX
        
        # Get parent disk
        $vhd = Get-VHD -Path $currentVHDX -ErrorAction Stop
        $currentVHDX = $vhd.ParentPath
    }
    
    return $chain
}

Write-Host "========================================="
Write-Host "VHDX Chain Merge Tool"
Write-Host "========================================="
Write-Host "Export Path: $ExportPath"
if ($WhatIf) {
    Write-Host "Mode: WhatIf (Preview only)"
}
Write-Host ""

# Validate export path structure
$vhdDir = Join-Path $ExportPath "Virtual Hard Disks"
if (-not (Test-Path $vhdDir)) {
    throw "Invalid export path. 'Virtual Hard Disks' directory not found."
}

# Find all VHDX files
$vhdxFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhdx" | Sort-Object Name
if ($vhdxFiles.Count -eq 0) {
    Write-Host "No VHDX files found. Nothing to merge."
    exit 0
}

Write-Host "Found $($vhdxFiles.Count) VHDX file(s):"
$vhdxFiles | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host ""

# Process each VHDX file
$mergeOperations = @()

foreach ($vhdxFile in $vhdxFiles) {
    Write-Host "Analyzing: $($vhdxFile.Name)"
    
    try {
        $chain = Get-VHDXChain -VHDXPath $vhdxFile.FullName
        
        if ($chain.Count -eq 1) {
            Write-Host "  [OK] No chain detected (standalone disk)"
        }
        else {
            Write-Host "  [!] Chain detected with $($chain.Count) disk(s):"
            for ($i = 0; $i -lt $chain.Count; $i++) {
                $indent = "    " + ("  " * $i)
                $diskName = Split-Path $chain[$i] -Leaf
                if ($i -eq 0) {
                    Write-Host "$indent|- $diskName (leaf - will be merged)"
                }
                elseif ($i -eq $chain.Count - 1) {
                    Write-Host "$indent|- $diskName (root parent)"
                }
                else {
                    Write-Host "$indent|- $diskName (intermediate)"
                }
            }
            
            $mergeOperations += @{
                LeafDisk = $chain[0]
                ChainCount = $chain.Count
                Chain = $chain
            }
        }
    }
    catch {
        Write-Warning "Failed to analyze $($vhdxFile.Name): $_"
    }
    
    Write-Host ""
}

if ($mergeOperations.Count -eq 0) {
    Write-Host "No disk chains found that need merging."
    exit 0
}

# Check for shared parents - this would cause corruption
Write-Host "Checking for shared parent disks..."
$parentUsage = @{}
foreach ($op in $mergeOperations) {
    # Skip the leaf disk (index 0) and count parent usage
    for ($i = 1; $i -lt $op.Chain.Count; $i++) {
        $parentDisk = $op.Chain[$i]
        if (-not $parentUsage.ContainsKey($parentDisk)) {
            $parentUsage[$parentDisk] = @()
        }
        $parentUsage[$parentDisk] += $op.LeafDisk
    }
}

# Check if any parent is used by multiple children
$sharedParents = @()
foreach ($parent in $parentUsage.Keys) {
    if ($parentUsage[$parent].Count -gt 1) {
        $parentName = Split-Path $parent -Leaf
        $children = $parentUsage[$parent] | ForEach-Object { Split-Path $_ -Leaf }
        Write-Host "  [!] WARNING: Parent disk '$parentName' is shared by multiple children:"
        $children | ForEach-Object { Write-Host "      - $_" }
        $sharedParents += $parent
    }
}

if ($sharedParents.Count -gt 0) {
    Write-Host ""
    Write-Host "========================================="
    Write-Host "ERROR: Shared parent disks detected!"
    Write-Host "========================================="
    Write-Host "Cannot safely merge disk chains when multiple differencing disks"
    Write-Host "share the same parent. Merging would corrupt the other chains."
    Write-Host ""
    Write-Host "This typically happens when:"
    Write-Host "- A VM has multiple disks created from the same base/template disk"
    Write-Host "- Multiple disks were cloned from a shared data disk"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "1. Create a copy of the parent disk for each differencing disk"
    Write-Host "2. Use -WhatIf to preview which disks need attention"
    Write-Host "3. Manually merge using Hyper-V Manager -> Edit Disk"
    Write-Host "4. Keep the differencing structure if merging is not required"
    Write-Host "========================================="
    exit 1
}

Write-Host "  [OK] No shared parents detected"
Write-Host ""

Write-Host "========================================="
Write-Host "Merge Operations Required: $($mergeOperations.Count)"
Write-Host "========================================="

foreach ($op in $mergeOperations) {
    $leafName = Split-Path $op.LeafDisk -Leaf
    Write-Host ""
    Write-Host "Merging chain for: $leafName"
    Write-Host "  Chain depth: $($op.ChainCount) disk(s)"
    
    if ($WhatIf) {
        Write-Host "  [WhatIf] Would merge all parent disks into: $leafName"
    }
    else {
        # Create a temporary backup of the leaf disk
        $backupPath = "$($op.LeafDisk).backup"
        $backupCreated = $false
        
        try {
            Write-Host "  Creating safety backup..."
            Copy-Item -Path $op.LeafDisk -Destination $backupPath -Force
            $backupCreated = $true
            
            # For exported VMs, we need to merge the differencing disk into its parent
            # The last item in the chain is the root parent
            $rootParent = $op.Chain[$op.Chain.Count - 1]
            $rootParentName = Split-Path $rootParent -Leaf
            
            Write-Host "  Merging disk chain..."
            Write-Host "    Merging $leafName into parent $rootParentName"
            
            # Merge the differencing disk into its immediate parent
            # This modifies the parent disk in place
            Merge-VHD -Path $op.LeafDisk -Force -ErrorAction Stop
            
            # Now the parent disk contains all the merged data
            # The differencing disk is now just a pointer and can be deleted
            
            # We need to swap the files to maintain the VM reference
            Write-Host "  Swapping disks to maintain VM reference..."
            
            # Create a temporary name for the parent
            $tempPath = "$rootParent.tmp"
            
            # Move parent to temp name
            Move-Item -Path $rootParent -Destination $tempPath -Force
            
            # Remove the now-empty differencing disk
            Remove-Item -Path $op.LeafDisk -Force
            
            # Move the merged parent (temp) to the leaf name
            Move-Item -Path $tempPath -Destination $op.LeafDisk -Force
            
            # Verify the final disk has no parent
            Write-Host "  Verifying merged disk..."
            $mergedVHD = Get-VHD -Path $op.LeafDisk -ErrorAction Stop
            if ($mergedVHD.ParentPath) {
                throw "Merge failed - disk still has parent: $($mergedVHD.ParentPath)"
            }
            
            Write-Host "  [OK] Successfully merged into single disk"
            
            # Clean up any intermediate parent disks
            for ($i = 1; $i -lt $op.Chain.Count - 1; $i++) {
                $intermediateDisk = $op.Chain[$i]
                if (Test-Path $intermediateDisk) {
                    Write-Host "  Removing intermediate disk: $(Split-Path $intermediateDisk -Leaf)"
                    Remove-Item -Path $intermediateDisk -Force
                }
            }
            
            # Remove backup
            if ($backupCreated -and (Test-Path $backupPath)) {
                Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Restore from backup on failure
            Write-Error "Failed to merge $leafName : $_"
            if ($backupCreated -and (Test-Path $backupPath)) {
                Write-Host "  Restoring from backup..."
                Copy-Item -Path $backupPath -Destination $op.LeafDisk -Force
                Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
            }
            throw
        }
    }
}

Write-Host ""
Write-Host "========================================="
if ($WhatIf) {
    Write-Host "Preview complete. Use without -WhatIf to execute."
}
else {
    Write-Host "[OK] All disk chains successfully merged!"
}
Write-Host "========================================="