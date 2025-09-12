# VM Repacking Documentation

## Overview
The repacking feature allows you to take an existing Hyper-V VM export and re-generalize it as a new catlet template. This process:
- Ensures cloud-init/cloudbase-init is installed and reset
- Runs cleanup and generalization scripts
- Applies eryph-specific post-processing via catletlify

## Usage

### Basic Usage
```powershell
# For Windows VMs
.\repack.ps1 -ExportPath "C:\Exports\MyWindowsVM" -OSType windows

# For Ubuntu/Linux VMs
.\repack.ps1 -ExportPath "C:\Exports\MyUbuntuVM" -OSType ubuntu

# With custom output name
.\repack.ps1 -ExportPath "C:\Exports\MyVM" -OSType windows -OutputName "custom-template"

# Minimal cleanup (faster, skips defrag)
.\repack.ps1 -ExportPath "C:\Exports\MyVM" -OSType windows -MinimalCleanup
```

## Known Issues

### TPM and Secure Boot Limitation
**Problem**: Packer's hyperv-vmcx builder has a critical limitation where it ALWAYS attempts to call `Set-VMFirmware`, even when not explicitly configuring secure boot. This fails on VMs that have TPM initialized with the error:
```
Cannot modify the secure boot template ID property after the virtual TPM is initialized
```

**Status**: This is a known issue with an unmerged fix: https://github.com/hashicorp/packer-plugin-hyperv/pull/137

**Current Limitation**: VMs with TPM enabled CANNOT be repacked using this tool. The script will detect TPM and provide instructions.

**Workaround**: To repack a VM that has TPM:
1. Import the VM manually in Hyper-V
2. Disable TPM using PowerShell: `Disable-VMTPM -VM $vm`
3. Re-export the VM
4. Use the new export with this repack script

**Alternative**: Use VMs that were created without TPM enabled for repacking.

## What Gets Reset/Cleaned

### Windows VMs
- Cloudbase-init state and logs (reset for next boot)
- Temporary files and event logs
- Chef installation (removed after use)
- Sysprep (generalizes Windows)
- Administrator password (randomized)
- Disk defragmentation (unless -MinimalCleanup)

### Linux VMs
- Cloud-init state (cloud-init clean)
- Machine ID (regenerated on next boot)
- SSH host keys (regenerated on next boot)
- Package cleanup (old kernels, headers, etc.)
- Disk space optimization (unless -MinimalCleanup)

## Requirements
- Hyper-V enabled on the build host
- External Hyper-V switch (auto-detected or specify with -SwitchName)
- Valid credentials for the VM (defaults: Administrator/packer for Windows, packer/packer for Linux)
- Sufficient disk space for VM operations

## Architecture
The repack process uses:
1. **Packer hyperv-vmcx source**: Imports and works with existing VM exports
2. **Chef Solo** (Windows): Runs cleanup recipes
3. **Shell scripts** (Linux): Runs cleanup scripts
4. **catletlify.ps1**: Applies eryph-specific transformations
5. **Same output structure**: Produces stage0 and stage1 outputs like fresh builds

## Troubleshooting

### WinRM Connection Issues
- Ensure Windows Remote Management is enabled in the source VM
- Check firewall rules allow WinRM
- Verify credentials are correct

### SSH Connection Issues
- Ensure SSH is installed and running in the Linux VM
- Check that password authentication is enabled
- Verify credentials are correct

### Packer Plugin Issues
If Packer fails to initialize plugins, manually initialize them:
```powershell
cd templates\windows
..\..\tools\packer.exe init windows-repack.pkr.hcl
```

## Future Improvements
- Automatic TPM handling (requires Packer plugin update)
- Support for more OS types
- Credential-less execution via offline mounting
- Parallel processing of multiple VMs