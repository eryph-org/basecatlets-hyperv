# RHEL-Compatible Templates

This directory contains Packer templates for building RHEL-compatible virtual machines for the eryph platform. The templates are designed to work with AlmaLinux, Oracle Linux, and RHEL distributions.

## Available Templates

### Active Templates (Ready to Build)
- **almalinux-8** - AlmaLinux 8.10 (free, publicly available ISO)
- **almalinux-9** - AlmaLinux 9.4 (free, publicly available ISO)
- **oracle-8** - Oracle Linux 8.10 (free, publicly available ISO)
- **oracle-9** - Oracle Linux 9.4 (free, publicly available ISO)

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
- **Hyper-V Gen 2** - UEFI boot with secure boot support
- **No swap partition** - Follows Azure best practices

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

### Modifying Provisioning
The `scripts/` directory contains modular provisioning scripts:
- `update.sh` - System updates and package installation
- `networking.sh` - Network configuration
- `hyperv.sh` - Hyper-V integration services
- `azure.sh` - Azure Linux Agent configuration
- `cloud-init.sh` - Cloud-init setup
- `cleanup.sh` - System cleanup for imaging

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
- Includes Unbreakable Enterprise Kernel option

### RHEL
- The original Red Hat Enterprise Linux
- Requires subscription for downloads
- Free developer subscription allows 16 systems
- Full commercial support available

## Troubleshooting

### Common Issues
1. **ISO Download Fails**: Check internet connection and ISO URLs
2. **Kickstart Timeout**: Increase boot_wait time in .pkrvars.hcl
3. **Package Installation Fails**: Check repository availability
4. **SSH Connection Fails**: Verify network configuration and credentials

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