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
    [string]$AzureStorageAccount,  # Azure storage account name

    [Parameter(ParameterSetName='AzureUpload', Mandatory=$true)]
    [string]$AzureContainerName,  # Azure storage container name

    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [string]$AzureBlobName,  # Name for the VHD blob (defaults to OutputName)

    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [string]$AzureSubscriptionId,  # Azure subscription ID (uses current context if not specified)

    [Parameter(ParameterSetName='AzureUpload', Mandatory=$false)]
    [int]$AzureCapMbps = 50  # Network bandwidth cap in Mbps for Azure upload
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

# Verify Azure credentials if Azure upload is enabled
if ($PSCmdlet.ParameterSetName -eq 'AzureUpload') {
    Write-Host "Verifying Azure CLI credentials before starting repack..."

    try {
        # Check if Azure CLI is available
        $azVersion = az version 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI is not installed or not in PATH"
        }

        # Check if logged in to Azure
        $azAccount = az account show 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $azAccount) {
            throw "Not logged in to Azure. Run 'az login' first."
        }

        # Set Azure subscription if provided
        if ($AzureSubscriptionId) {
            Write-Host "Setting Azure subscription to: $AzureSubscriptionId"
            az account set --subscription $AzureSubscriptionId 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to set Azure subscription to: $AzureSubscriptionId"
            }
            $azAccount = az account show | ConvertFrom-Json
        }

        Write-Host "[OK] Azure CLI credentials verified"
        Write-Host "  Subscription: $($azAccount.name) ($($azAccount.id))"
        Write-Host "  Account: $($azAccount.user.name)"
        Write-Host "  Tenant: $($azAccount.tenantId)"

        # Verify storage account exists
        Write-Host "Verifying storage account: $AzureStorageAccount"
        $storageAccount = az storage account show --name "$AzureStorageAccount" --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $storageAccount) {
            throw "Storage account '$AzureStorageAccount' not found or not accessible"
        }
        Write-Host "[OK] Storage account verified: $AzureStorageAccount"

    } catch {
        Write-Host "Azure CLI credentials verification failed: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure:"
        Write-Host "1. Azure CLI is installed: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        Write-Host "2. You are logged in: az login"
        Write-Host "3. You have access to subscription: $(if ($AzureSubscriptionId) { $AzureSubscriptionId } else { 'current' })"
        Write-Host "4. Storage account exists and is accessible: $AzureStorageAccount"
        Write-Host ""
        throw "Azure credentials verification failed. Please fix the above issues and try again."
    }

    Write-Host ""
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

# Check if build already exists (for repeatability) - always check stage1 (final output)
$buildPath = ".\builds\$OutputName-stage1"
if (Test-Path $buildPath) {
    Write-Host "`nExisting build found: $buildPath"

    # Look for VHD files in VM subdirectory (catletlify structure)
    $vmSubDir = Get-ChildItem -Path $buildPath -Directory | Select-Object -First 1
    if ($vmSubDir) {
        $vhdDir = Join-Path $vmSubDir.FullName "Virtual Hard Disks"
        if (Test-Path $vhdDir) {
            $vhdFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhd*"
            if ($vhdFiles.Count -gt 0) {
                Write-Host "Build appears complete with VHD files:"
                foreach ($vhd in $vhdFiles) {
                    Write-Host "  - $($vhd.Name)"
                }

                if ($PSCmdlet.ParameterSetName -eq 'AzureUpload') {
                    Write-Host "`nSkipping repack and catletlify - proceeding directly to Azure upload..."
                    $skipRepack = $true
                } else {
                    Write-Host "`nSkipping repack and catletlify - build already complete at: $buildPath"
                    exit 0
                }
            } else {
                Write-Host "Build directory exists but no VHD files found - will rebuild"
                $skipRepack = $false
            }
        } else {
            Write-Host "Build directory exists but no Virtual Hard Disks found - will rebuild"
            $skipRepack = $false
        }
    } else {
        Write-Host "Build directory exists but no VM subdirectory found - will rebuild"
        $skipRepack = $false
    }
} else {
    Write-Host "`nNo existing build found - will create new build"
    $skipRepack = $false
}

try {
    if (-not $skipRepack) {
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

    # Navigate to OS-specific template directory and run Packer
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
} # End of skipRepack check

# Handle output based on parameter set
$isAzureUpload = $PSCmdlet.ParameterSetName -eq 'AzureUpload'
    
    if ($isAzureUpload) {
        # Azure upload workflow
        Write-Host "`n==========================================="
        Write-Host "Preparing for Azure upload"
        Write-Host "==========================================="
        Write-Host "Storage Account: $AzureStorageAccount"
        Write-Host "Container: $AzureContainerName"

        # Run catletlify only if we ran the repack (stage0 exists)
        if (-not $skipRepack) {
            Write-Host "`nRunning catletlify to standardize disk naming..."
            & .\tools\catletlify.ps1 -BasePath .\builds -TemplateName $OutputName

            if ($LASTEXITCODE -ne 0) {
                throw "Catletlify failed with exit code $LASTEXITCODE"
            }
        } else {
            Write-Host "`nSkipping catletlify - using existing stage1 build"
        }

        # Set blob prefix if not provided
        $blobPrefix = if ($AzureBlobName) { $AzureBlobName } else { $OutputName }

        & .\tools\upload-to-azure.ps1 `
            -BuildPath ".\builds\$OutputName-stage1" `
            -StorageAccount $AzureStorageAccount `
            -ContainerName $AzureContainerName `
            -BlobPrefix $blobPrefix `
            -SubscriptionId $AzureSubscriptionId `
            -CapMbps $AzureCapMbps

        if ($LASTEXITCODE -ne 0) {
            throw "Azure upload failed with exit code $LASTEXITCODE"
        }

        Write-Host "`n==========================================="
        Write-Host "Azure upload completed successfully!"
        Write-Host "Storage Account: $AzureStorageAccount"
        Write-Host "Container: $AzureContainerName"
        Write-Host "Blob Prefix: $blobPrefix"
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