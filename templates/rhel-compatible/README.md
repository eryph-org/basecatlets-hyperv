# RHEL-Compatible Templates

This directory contains Packer templates for building RHEL-compatible virtual machines for the eryph platform. The templates are designed to work with AlmaLinux, Oracle Linux, and RHEL distributions.

## Available Templates

### Active Templates (Ready to Build)
- **almalinux-8** - AlmaLinux 8.10 (free, publicly available ISO)
- **almalinux-9** - AlmaLinux 9.6 (free, publicly available ISO)
- **almalinux-10** - AlmaLinux 10.0 (new major release, free, publicly available ISO)
- **oracle-8** - Oracle Linux 8.9 (free, publicly available ISO)
- **oracle-9** - Oracle Linux 9.5 (free, publicly available ISO)
- **oracle-10** - Oracle Linux 10.0 (new major release, free, publicly available ISO)

### Example Templates (User Must Provide ISOs)
- **rhel-8.pkrvars.hcl.example** - RHEL 8 template (requires Red Hat subscription)
- **rhel-9.pkrvars.hcl.example** - RHEL 9 template (requires Red Hat subscription)

## Building Templates

### Using the Main Build Script
```powershell
# Build specific template
.\build.ps1 -Filter "almalinux-8"

# List all available templates
.\list.ps1

# Build all RHEL-compatible templates
.\build.ps1 -Filter "rhel-compatible"
```

### Using Packer Directly
```powershell
# From the rhel-compatible directory
packer init -upgrade .
packer build -var-file="almalinux-8.pkrvars.hcl" rhel-base.pkr.hcl
```

## Template Features

### Cloud Compatibility
- **NoCloud datasource** - For eryph platform
- **Azure datasource** - For Microsoft Azure
- **Hyper-V Gen 2** - UEFI boot with secure boot enabled (modern RHEL-compatible distributions support this)
- **No swap partition** - Follows Azure best practices
- **Microsoft compliance** - Follows official Hyper-V and Azure documentation requirements

### Partition Layout
```
/boot/efi - 200MB (EFI System Partition)
/boot     - 1GB (XFS filesystem)
/         - Remaining space (XFS filesystem, expandable)
```

### Included Packages
- `cloud-init` - Cloud initialization
- `hyperv-daemons` - Hyper-V integration services
- `WALinuxAgent` - Azure Linux Agent
- Essential system utilities

### Services Configuration
- All cloud-init services enabled
- WALinuxAgent configured for cloud-init compatibility
- SSH enabled with optimized configuration
- NetworkManager for network management

## Using RHEL

To use RHEL instead of the free alternatives:

1. **Get RHEL Access**:
   - Sign up for Red Hat Developer subscription (free): https://developers.redhat.com/
   - Download RHEL ISO from the developer portal

2. **Create Variable File**:
   ```powershell
   # Copy example file
   copy rhel-8.pkrvars.hcl.example rhel-8.pkrvars.hcl

   # Edit the file and update:
   # - iso_url with your RHEL ISO path or URL
   # - iso_checksum with the actual checksum
   ```

3. **Build**:
   ```powershell
   packer build -var-file="rhel-8.pkrvars.hcl" rhel-base.pkr.hcl
   ```

## Customization

### Adding New Distributions
1. Create a new `.pkrvars.hcl` file following the existing pattern
2. Update `build.json` to include the new template
3. Test the build process

### Templating System
Uses Packer's templating system for maximum reusability:
- **`ks.pkrtpl.hcl`** - Templated kickstart file with variables
- **Distribution-specific variables** in `.pkrvars.hcl` files:
  - `kernel_packages` - Which kernel to install
  - `kernel_exclusions` - Which kernels to exclude
  - `distro_specific_post` - Distribution-specific post-install commands

### Modifying Provisioning
The `scripts/` directory contains modular provisioning scripts:
- `update.sh` - System updates and package installation
- `networking.sh` - Network configuration
- `hyperv.sh` - Hyper-V integration services
- `azure.sh` - Azure Linux Agent configuration
- `cloud-init.sh` - Cloud-init setup
- `cleanup.sh` - System cleanup for imaging

### Variable Examples

**AlmaLinux/RHEL (Standard Kernel)**:
```hcl
kernel_packages = "kernel\nkernel-devel"
kernel_exclusions = ""
distro_specific_post = ""
```

**Oracle Linux (UEK Kernel)**:
```hcl
kernel_packages = "kernel-uek\nkernel-uek-devel"
kernel_exclusions = "-kernel\n-kernel-devel"
distro_specific_post = "# Set UEK kernel as default boot option\ngrub2-set-default 0"
```

## Distribution Notes

### AlmaLinux
- Binary compatible with RHEL
- Backed by CloudLinux with $1M annual funding
- Fast security updates
- Enterprise-focused

### Oracle Linux
- 100% binary compatible with RHEL
- Free for production use
- Backed by Oracle
- **Uses UEK kernel** (Unbreakable Enterprise Kernel) - Microsoft's recommendation for Hyper-V/Azure
- Better performance than RHCK kernel (16% improvement in benchmarks)
- **Note**: Oracle Linux templates use placeholder checksums - verify actual checksums from Oracle's checksum files before building

### RHEL
- The original Red Hat Enterprise Linux
- Requires subscription for downloads
- Free developer subscription allows 16 systems
- Full commercial support available

## Troubleshooting

### Common Issues
1. **Invalid Checksum Error**:
   - For Oracle Linux 8/9/10: Download checksum file from https://linux.oracle.com/security/gpg/archive.html
   - Look for files like `OracleLinux-R8-U9-Server-x86_64.checksum`, `OracleLinux-R9-U5-Server-x86_64.checksum`, `OracleLinux-R10-U0-Server-x86_64.checksum`
   - Extract the SHA256 checksum and replace placeholder in .pkrvars.hcl file
   - For AlmaLinux: Check https://repo.almalinux.org/almalinux/[version]/isos/x86_64/CHECKSUM
2. **ISO Download Fails**: Check internet connection and ISO URLs
3. **Kickstart Timeout**: Increase boot_wait time in .pkrvars.hcl
4. **Package Installation Fails**: Check repository availability
5. **SSH Connection Fails**: Verify network configuration and credentials

### Debug Mode
Add `-debug` flag to packer build for step-by-step execution:
```powershell
packer build -debug -var-file="almalinux-8.pkrvars.hcl" rhel-base.pkr.hcl
```

## Best Practices

1. **Minimal Installation**: Templates install only essential packages
2. **Security**: SELinux in permissive mode, firewall disabled during build
3. **Cloud-Ready**: Configured for both NoCloud and Azure datasources
4. **Expandable**: Root partition can grow to fill available disk space
5. **Service Isolation**: Each service configured independently for reliability

## Integration with eryph

These templates create base catlets that:
- Boot quickly in Hyper-V environments
- Support eryph's fodder system via cloud-init
- Use Linux-style naming (eth0, sda) for consistency
- Include eryph guest services for platform integration