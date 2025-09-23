# Azure Linux Templates for eryph

This directory contains templates for building Azure Linux (formerly CBL-Mariner) virtual machines optimized for the eryph platform. Unlike traditional Packer-based templates, Azure Linux uses Microsoft's official toolkit to build VHD images directly.

## Overview

Azure Linux is Microsoft's lightweight Linux distribution designed for cloud and edge services. These templates create eryph-compatible catlet base images with:

- **Cloud-init integration** for eryph fodder system
- **Hyper-V optimizations** for catlet environments
- **NoCloud datasource** for eryph metadata injection
- **Minimal footprint** optimized for containers and VMs

## Prerequisites

### Required Software
- **Windows Subsystem for Linux (WSL)** - Azure Linux toolkit runs in WSL
- **Git** - For downloading the Azure Linux toolkit
- **PowerShell 7+** - For running build scripts

### WSL Setup
```powershell
# Install WSL if not already installed
wsl --install

# Ensure WSL is running
wsl --status
```

## Build Process

### Quick Start
```powershell
# Build Azure Linux image
.\build.ps1 -Filter "azure-linux-3"

# Clean build (removes previous toolkit)
.\build.ps1 -Filter "azure-linux-3" -Clean
```

### Available Build Targets
- **azure-linux-3** - VHDX image for Hyper-V Generation 2 VMs (UEFI)

## How It Works

### 1. Toolkit Download
The build script downloads Microsoft's Azure Linux toolkit:
- **Repository**: https://github.com/microsoft/azurelinux
- **Version**: 3.0 (latest stable)
- **Method**: Shallow git clone

### 2. Custom Configuration
The script copies our eryph-specific configurations:
- **imageconfigs/eryph-core-efi.json** - Image layout and package specification
- **imageconfigs/eryph-packages.json** - Package list with eryph requirements
- **scripts/** - Customization scripts for eryph integration

### 3. Image Build
Using Azure Linux's official build method:
```bash
wsl sudo make image -j8 CONFIG_FILE=./imageconfigs/eryph-core-efi.json
```

### 4. Output Processing
- Built images are placed in `../../builds/azure-linux-3-gen2-stage0/`
- Ready for catletlify.ps1 post-processing (stage1)

## Image Configuration

### Disk Layout (UEFI)
```
/dev/sda1 (ESP)     - 200MB  - EFI System Partition
/dev/sda2 (/boot)   - 1GB    - Boot partition (ext4)
/dev/sda3 (/)       - ~63GB  - Root filesystem (ext4)
```

### Package Selection
**Core System:**
- Linux kernel with Hyper-V drivers
- systemd init system
- GRUB2 EFI bootloader

**Cloud Integration:**
- cloud-init for eryph fodder system
- hyperv-daemons for Hyper-V integration
- NetworkManager for network management

**eryph Specific:**
- NoCloud datasource configuration
- Hyper-V optimizations
- eryph service placeholders

### Customization Scripts

**configure-cloud-init.sh:**
- Sets up NoCloud datasource priority
- Configures Azure fallback datasource
- Disables network config conflicts
- Creates eryph metadata directories

**setup-hyperv.sh:**
- Loads Hyper-V kernel modules
- Optimizes systemd timeouts
- Configures network interface naming (eth0, eth1)
- Sets up KVP daemon integration

**eryph.sh:**
- Downloads and installs actual eryph guest services
- Creates systemd service for eryph-guest-services
- Enables and starts eryph services
- Handles version management and updates

**cleanup.sh:**
- Removes temporary packer user
- Clears logs, cache, and temporary files
- Removes SSH host keys (regenerated on first boot)
- Clears cloud-init cache for fresh deployment
- Zeros free space for better compression

## Integration with eryph Build Pipeline

### Stage 0 (This Template)
```
azure-linux-3-stage0/
└── azure-linux-3.vhdx
```

### Stage 1 (catletlify.ps1)
```
azure-linux-3-stage1/
├── azure-linux-3.vhdx
├── vm.json
└── metadata/
```

## Troubleshooting

### WSL Issues
```powershell
# Check WSL status
wsl --status

# Restart WSL if needed
wsl --shutdown
wsl
```

### Build Failures
```powershell
# Clean build
.\build.ps1 -Clean

# Check WSL has required tools
wsl which make
wsl which sudo
```

### Permission Issues
```powershell
# WSL may need elevated permissions for sudo operations
# Ensure your WSL user has sudo privileges
```

## Comparison with Other Templates

| Feature | Ubuntu | RHEL-Compatible | Azure Linux |
|---------|---------|-----------------|-------------|
| Build Method | Packer + autoinstall | Packer + kickstart | Azure toolkit |
| Base Size | ~2GB | ~1.5GB | ~800MB |
| Boot Time | Medium | Medium | Fast |
| Memory Usage | Higher | Medium | Lower |
| Package Manager | apt | dnf/yum | tdnf |
| Init System | systemd | systemd | systemd |
| Container Runtime | docker/containerd | docker/podman | containerd |

## Advanced Usage

### Custom Package Lists
Edit `imageconfigs/eryph-packages.json` to add/remove packages:
```json
{
    "packages": [
        "filesystem",
        "kernel",
        "your-custom-package"
    ]
}
```

### Custom Scripts
Add scripts to `scripts/` directory and reference in `eryph-core-efi.json`:
```json
{
    "AdditionalFiles": {
        "./resources/scripts/eryph/your-script.sh": "/tmp/your-script.sh"
    },
    "PostInstallScripts": [
        {
            "Path": "/tmp/your-script.sh"
        }
    ]
}
```

## Azure Linux Resources

- **Official Repository**: https://github.com/microsoft/azurelinux
- **Documentation**: https://microsoft.github.io/azure-linux-image-tools/
- **Packages**: https://packages.microsoft.com/azurelinux/3.0/prod/
- **Community**: https://github.com/microsoft/azurelinux/discussions

## License

This template configuration is provided under the same license as the eryph project. Azure Linux itself is released under the MIT license by Microsoft.