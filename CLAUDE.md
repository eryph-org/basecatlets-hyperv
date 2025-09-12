# hyperv-boxes Repository Knowledge

## Overview
This repository builds Hyper-V virtual machine templates (base catlets) for the eryph platform. These VMs become the foundational volume genes published to the eryph genepool under the dbosoft organization (e.g., `dbosoft/ubuntu-22.04/latest`).

## Purpose
- Creates cloud-ready VM templates with cloud-init (Linux) or cloudbase-init (Windows)
- Optimizes VMs specifically for eryph catlets with standardized naming conventions
- Provides base images that eryph users inherit from when creating catlets
- Serves as a template/starting point for organizations creating their own base catlets

## Architecture

### Repository Structure
```
hyperv-boxes/
├── build.json           # Central configuration defining all OS templates
├── build.ps1            # Main build orchestrator script
├── list.ps1             # Lists available templates with filtering
├── tools/
│   ├── packer.exe       # HashiCorp Packer for VM building
│   ├── oscdimg.exe      # Windows ISO creation tool
│   └── catletlify.ps1   # Eryph-specific post-processing
├── templates/
│   ├── ubuntu/          # Ubuntu templates (20.04, 22.04, 24.04, 25.04)
│   └── windows/         # Windows templates (Server 2016-2025, Win 10/11)
├── packer_cache/        # Downloaded ISO cache
└── builds/              # Output directory for built VMs
```

### Build Process

#### Two-Stage Build
1. **Stage 0** (`*-stage0`): Packer builds the raw VM
   - Uses .pkr.hcl templates with .pkrvars.hcl for version-specific variables
   - Installs OS with unattended installation (autoinstall for Ubuntu, Autounattend for Windows)
   - Configures cloud-init/cloudbase-init
   - Runs provisioning scripts

2. **Stage 1** (`*-stage1`): catletlify.ps1 post-processing
   - Renames drives to Linux convention (sda, sdb, sdc)
   - Renames network adapters (eth0, eth1)
   - Enables processor migration compatibility
   - Exports VM metadata as JSON for eryph-packer
   - Applies VM setting overrides

#### Automation Pipeline
The eryph-genes repository orchestrates the complete pipeline:
1. `eryph-genes/build.ps1` calls `hyperv-boxes/build.ps1` with template filter
2. Built VMs are packed using `pack_build.ps1`
3. Testing via `test_packed.ps1` verifies the catlet boots and is accessible
4. Publishing to genepool (monthly rebuilds planned)

## Key Components

### catletlify.ps1
Critical post-processing script that:
- Adapts standard Hyper-V VMs for eryph requirements
- Creates consistent naming across Windows and Linux
- Exports metadata used by eryph-packer to generate catlet YAML
- Ensures migration compatibility between Hyper-V hosts

### Template Organization

#### Ubuntu Templates
- **Main template**: `ubuntu-autoinstall.pkr.hcl`
- **Variables**: `ubuntu-XX.04.pkrvars.hcl` (20.04, 22.04, 24.04, 25.04)
- **Key features**:
  - linux-azure kernel for cloud optimization
  - EFI boot for Hyper-V Gen 2
  - cloud-init configuration
  - No recovery partition

#### Windows Templates
- **Main template**: `windows.pkr.hcl`
- **Variables**: Multiple .pkrvars.hcl for different editions
- **Key features**:
  - Chef Solo for system configuration
  - Multiple Windows Update cycles
  - Cloudbase-init for cloud-init equivalent
  - TPM and secure boot for Windows 11
  - Sysprep for template preparation

## Supported Operating Systems

### Linux
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Ubuntu 25.04

### Windows Server
- Windows Server 2016 (Standard, Standard Core, Datacenter)
- Windows Server 2019 (Standard, Standard Core, Datacenter)
- Windows Server 2022 (Standard, Standard Core, Datacenter)
- Windows Server 2025 (Standard, Standard Core, Datacenter)

### Windows Client
- Windows 10 (2004, 20H2) Enterprise
- Windows 11 (21H1, 22H2, 24H2) Enterprise

## File Types
- `.pkr.hcl` - Packer HCL configuration files
- `.pkrvars.hcl` - Packer variable files for specific OS versions
- `.pkrtpl.hcl` - Packer template files for dynamic content generation
- `.ps1` - PowerShell scripts for provisioning and build orchestration
- `.sh` - Shell scripts for Linux provisioning

## Integration with eryph

### Naming Conventions
Eryph requires Linux-style naming for consistency:
- **Drives**: sda, sdb, sdc (not C:, D:, E:)
- **Network**: eth0, eth1 (not Ethernet, Network Adapter)

### Cloud-Init/Cloudbase-Init
- Enables eryph's fodder system to work
- Fodder becomes cloud-init/cloudbase-init configuration
- Runs on first boot to configure the VM

### Volume Genes
Built VMs become volume genes in the genepool:
- Compressed VHDX files with metadata
- Tagged by date (20241216) or as "latest"
- Published under dbosoft organization
- Form the base for catlet inheritance chains

## Testing
The `test_packed.ps1` script (in eryph-genes repo):
1. Deploys a test catlet from the built gene
2. Verifies VM boots and becomes accessible
3. For Windows: Checks sysprep completion and packer user removal
4. For Linux: Verifies SSH access with generated key
5. Cleans up test resources

## Usage

### Building Templates
```powershell
# List available templates
.\list.ps1

# Build specific template
.\build.ps1 -Filter "ubuntu-22.04"

# Build all templates
.\build.ps1
```

### Customization
This repository is designed as a template for organizations to:
1. Fork and modify for custom requirements
2. Add organization-specific configurations
3. Build private base catlets for internal use
4. Publish to private or public genepools

## Important Notes

### Version Strategy
- Ubuntu versions follow Ubuntu's naming (25.04 is not beta, it's Ubuntu's version scheme)
- Windows versions align with Microsoft's release names
- Monthly rebuilds planned for security updates

### Dependencies
- Requires Hyper-V enabled on build host
- Needs sufficient disk space for ISO cache and VM builds
- Internet access for downloading ISOs and updates

### Security
- Base images are minimal, security hardening is user's responsibility
- Starter variants include default credentials (admin/admin) for testing only
- Production use should add proper authentication via fodder

## Related Repositories
- **eryph-genes**: Orchestrates building, packing, testing, and publishing
- **eryph**: Main platform repository
- **eryph-packer**: Tool for creating and managing genes

## Best Practices
1. Test locally before publishing to genepool
2. Keep base images minimal - users add specifics via fodder
3. Document changes in commit messages
4. Version appropriately (semantic, date-based, or floating tags)
5. Enable cloud-init/cloudbase-init for fodder support