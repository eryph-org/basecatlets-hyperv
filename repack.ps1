[CmdletBinding(DefaultParameterSetName='Local')]
param (
    # Common parameters (available in all parameter sets)
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$ExportPath,  # Path to Hyper-V VM export directory
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateSet('windows', 'ubuntu', 'linux')]
    [string]$OSType,  # OS type determines which cleanup method to use
    
    [Parameter(Mandatory=$false)]
    [string]$OutputName,  # Optional output name (defaults to OSType-repack-timestamp)
    
    [Parameter(Mandatory=$false)]
    [string]$Username,  # VM credentials
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$SwitchName,  # Hyper-V switch (auto-detected if not provided)
    
    [Parameter(Mandatory=$false)]
    [switch]$MinimalCleanup,  # Only essential cleanup (no defrag, etc.)
    
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$VMOverridesPath,  # Optional path to vm-overrides.json file
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDiskMerge,  # Skip merging VHDX chains (use with caution)
    
    # Local parameter set (default) - output for eryph
    [Parameter(ParameterSetName='Local')]
    [switch]$SkipCatletlify,  # Skip catletlify post-processing
    
    # Azure upload parameter set - convert and upload to Azure
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$true)]
    [switch]$UploadToAzure,  # Enable Azure upload workflow
    
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$true)]
    [string]$AzureResourceGroup,  # Azure resource group for the image
    
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [string]$AzureLocation = 'eastus',  # Azure region
    
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [string]$AzureImageName,  # Name for Azure managed image (defaults to OutputName)
    
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [ValidateSet('Premium_LRS', 'Standard_LRS', 'StandardSSD_LRS', 'UltraSSD_LRS', 'Premium_ZRS', 'StandardSSD_ZRS')]
    [string]$AzureStorageType = 'Premium_LRS',  # Azure disk storage type
    
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [string]$AzureSubscriptionId,  # Azure subscription ID (uses current context if not specified)
    
    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [switch]$SkipAzureImageCreation  # Only upload VHD, don't create managed image
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

# Validate export path structure
$vmDir = Join-Path $ExportPath "Virtual Machines"
if (-not (Test-Path $vmDir)) {
    throw "Invalid export path. Expected 'Virtual Machines' subdirectory not found."
}

$vmcxFile = Get-ChildItem -Path $vmDir -Filter "*.vmcx" | Select-Object -First 1
if (-not $vmcxFile) {
    throw "No .vmcx file found in export path."
}

# No TPM check - let Packer handle it or fail with its own error message

# Generate output name if not provided
if (-not $OutputName) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputName = "$OSType-repack-$timestamp"
}

# Set credential defaults based on OS type
if (-not $Username) {
    $Username = switch ($OSType) {
        'windows' { 'Administrator' }
        default   { 'packer' }
    }
}

if (-not $Password) {
    # Use default passwords for now - in production, should prompt
    $Password = switch ($OSType) {
        'windows' { 'MgP3?kh-@BkqKRvW' }
        default   { 'packer' }
    }
    Write-Warning "Using default password. Consider providing -Password parameter for security."
}

# Auto-detect switch if not provided
if ([string]::IsNullOrWhiteSpace($SwitchName)) {
    $SwitchName = (Get-VMSwitch -SwitchType External | Select-Object -First 1).Name
    if ([string]::IsNullOrWhiteSpace($SwitchName)) {
        throw 'Switch name not set and no external switch found'
    }
    Write-Host "Using auto-detected switch: $SwitchName"
}

# Generate metadata
$metadata = @{
    "_os_type" = if ($OSType -eq 'windows') { 'windows' } else { 'linux' }
    "_repack_source" = $ExportPath
    "build_date" = (Get-Date).ToString("s")
    "build_type" = "repack"
}

Write-Host "==========================================="
Write-Host "Repacking VM from: $ExportPath"
Write-Host "OS Type: $OSType"
Write-Host "Output Name: $OutputName"
Write-Host "Username: $Username"
Write-Host "==========================================="

# Prepare export by consolidating any differencing disks
if (-not $SkipDiskMerge) {
    Write-Host "`nPreparing export (consolidating differencing disks)..."
    if ($PSCmdlet.ParameterSetName -eq 'AzureUpload') {
        & .\tools\prepare-export-for-repack.ps1 -ExportPath $ExportPath -Force -Azure
    } else {
        & .\tools\prepare-export-for-repack.ps1 -ExportPath $ExportPath -Force
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to prepare export for repacking"
    }
} else {
    Write-Warning "Skipping disk consolidation - VM may have differencing disks!"
}

try {
    # Navigate to OS-specific template directory
    $templateDir = if ($OSType -eq 'ubuntu' -or $OSType -eq 'linux') { 'ubuntu' } else { 'windows' }
    $templatePath = Join-Path "templates" $templateDir
    Push-Location $templatePath
    
    try {
        # Select the ONE repack template for this OS type
        $repackTemplate = "$OSType-repack.pkr.hcl"
        
        # Check if repack template exists
        if (-not (Test-Path $repackTemplate)) {
            throw "Repack template not found: $repackTemplate"
        }
        
        # Prepare Packer variables
        $packerVars = @(
            "-var=export_path=$ExportPath",
            "-var=output_name=$OutputName",
            "-var=username=$Username",
            "-var=password=$Password",
            "-var=hyperv_switch=$SwitchName"
        )
        
        if ($MinimalCleanup) {
            $packerVars += "-var=minimal_cleanup=true"
        }
        
        # Configure patched Hyper-V plugin - use absolute path and clear defaults
        Write-Host "`nConfiguring patched Hyper-V plugin..."
        $patchedPluginPath = Resolve-Path "..\..\tools\plugins"
        $env:PACKER_PLUGIN_PATH = $patchedPluginPath.Path
        
        # Clear any cached plugins that might conflict
        $env:PACKER_CACHE_DIR = Join-Path $env:TEMP "packer_cache_repack"
        if (Test-Path $env:PACKER_CACHE_DIR) {
            Remove-Item -Path $env:PACKER_CACHE_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $env:PACKER_CACHE_DIR -Force | Out-Null
        
        Write-Host "`nSkipping packer init (using pre-installed patched plugin)..."
        Write-Host "Plugin Path: $env:PACKER_PLUGIN_PATH"
        Write-Host "Cache Dir: $env:PACKER_CACHE_DIR"
        
        Write-Host "`nStarting repack process with Packer (using patched Hyper-V plugin)..."
        Write-Host "Template: $repackTemplate"
        Write-Host "Variables: $($packerVars -join ' ')"
        
        # Run Packer build with patched plugin (skip init)
        & ..\..\tools\packer.exe build $packerVars $repackTemplate
        
        if ($LASTEXITCODE -ne 0) {
            throw "Packer build failed with exit code $LASTEXITCODE"
        }
        
        # Save metadata
        $metadataPath = Join-Path "..\..\builds\$OutputName-stage0" "metadata.json"
        $metadata | ConvertTo-Json | Set-Content -Path $metadataPath
        Write-Host "Metadata saved to: $metadataPath"
        
        # Copy VM overrides if provided
        if ($VMOverridesPath) {
            $overridesDestPath = Join-Path "..\..\builds\$OutputName-stage0" "vm-overrides.json"
            Copy-Item -Path $VMOverridesPath -Destination $overridesDestPath
            Write-Host "VM overrides copied to: $overridesDestPath"
        } else {
            Write-Host "No VM overrides provided - original VM settings will be preserved"
        }
        
    } finally {
        Pop-Location
    }
    
    # Handle output based on parameter set
    $isAzureUpload = $PSCmdlet.ParameterSetName -eq 'AzureUpload'
    
    if ($isAzureUpload) {
        # Azure upload workflow
        Write-Host "`n==========================================="
        Write-Host "Preparing for Azure upload"
        Write-Host "==========================================="
        Write-Host "Resource Group: $AzureResourceGroup"
        Write-Host "Location: $AzureLocation"
        Write-Host "Storage Type: $AzureStorageType"
        
        # Skip catletlify for Azure (not needed for Azure deployment)
        Write-Host "`nSkipping catletlify (not needed for Azure)"
        
        # Convert and upload to Azure
        $azureImageName = if ($AzureImageName) { $AzureImageName } else { $OutputName }
        
        & .\tools\upload-to-azure.ps1 `
            -BuildPath ".\builds\$OutputName-stage0" `
            -ResourceGroup $AzureResourceGroup `
            -Location $AzureLocation `
            -ImageName $azureImageName `
            -OSType $OSType `
            -StorageType $AzureStorageType `
            -SkipImageCreation:$SkipAzureImageCreation `
            -SubscriptionId $AzureSubscriptionId
            
        if ($LASTEXITCODE -ne 0) {
            throw "Azure upload failed with exit code $LASTEXITCODE"
        }
        
        Write-Host "`n==========================================="
        Write-Host "Azure upload completed successfully!"
        if (-not $SkipAzureImageCreation) {
            Write-Host "Azure managed image: $azureImageName"
        }
        Write-Host "Resource Group: $AzureResourceGroup"
        Write-Host "==========================================="
        
    } else {
        # Local/eryph workflow
        if (-not $SkipCatletlify) {
            Write-Host "`nRunning catletlify post-processing..."
            & .\tools\catletlify.ps1 -BasePath .\builds -TemplateName $OutputName
            
            if ($LASTEXITCODE -ne 0) {
                throw "Catletlify failed with exit code $LASTEXITCODE"
            }
            
            Write-Host "`n==========================================="
            Write-Host "Repack completed successfully!"
            Write-Host "Output: .\builds\$OutputName-stage1"
            Write-Host "==========================================="
        } else {
            Write-Host "`n==========================================="
            Write-Host "Repack completed successfully!"
            Write-Host "Output: .\builds\$OutputName-stage0 (catletlify skipped)"
            Write-Host "==========================================="
        }
    }
    
} catch {
    Write-Error "Repack failed: $_"
    exit 1
} finally {
    Pop-Location
}