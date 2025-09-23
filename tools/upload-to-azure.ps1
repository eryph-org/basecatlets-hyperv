[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$BuildPath,  # Path to build directory containing VHDX

    [Parameter(Mandatory=$true)]
    [string]$StorageAccount,  # Azure storage account name

    [Parameter(Mandatory=$true)]
    [string]$ContainerName,  # Azure storage container name

    [Parameter(Mandatory=$true)]
    [string]$BlobPrefix,  # Prefix path for VHD blobs in container (e.g., "disks/eryph/genepool")

    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,  # Azure subscription ID

    [Parameter(Mandatory=$false)]
    [int]$CapMbps = 50  # Network bandwidth cap in Mbps
)

$ErrorActionPreference = 'Stop'

Write-Host "==========================================="
Write-Host "Azure VHD Directory Upload to Blob Storage"
Write-Host "==========================================="
Write-Host "Build Path: $BuildPath"
Write-Host "Storage Account: $StorageAccount"
Write-Host "Container: $ContainerName"
Write-Host "Blob Prefix: $BlobPrefix"
Write-Host ""

# Check if Azure CLI is available
try {
    $azVersion = az version 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI is not installed or not in PATH"
    }
    Write-Host "Using Azure CLI version: $($azVersion.'azure-cli')"
} catch {
    throw "Azure CLI is required. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
}

# Check if azcopy is available in tools directory
$azcopyPath = Join-Path $PSScriptRoot "azcopy.exe"
if (-not (Test-Path $azcopyPath)) {
    throw @"
azcopy.exe not found in tools directory: $azcopyPath

Please download azcopy and place it in the tools directory:
1. Download from: https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10
2. Extract azcopy.exe to: $PSScriptRoot\azcopy.exe
3. Run this script again
"@
}

Write-Host "Using azcopy from: $azcopyPath"

# Test Azure credentials
Write-Host "Testing Azure credentials..."
try {
    # Verify we're logged in to Azure
    $account = az account show 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $account) {
        throw "Not logged in to Azure"
    }

    # Set Azure context if subscription ID is provided
    if ($SubscriptionId) {
        Write-Host "Setting Azure subscription context to: $SubscriptionId"
        az account set --subscription $SubscriptionId 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set subscription: $SubscriptionId"
        }
        $account = az account show | ConvertFrom-Json
    }

    Write-Host "Using Azure subscription: $($account.name)"
    Write-Host "Azure credentials verified successfully"

} catch {
    throw "Azure credentials test failed. Please login to Azure using 'az login': $_"
}

# Find Virtual Hard Disks directory in catletlify output structure
$vmSubDir = Get-ChildItem -Path $BuildPath -Directory | Select-Object -First 1
if (-not $vmSubDir) {
    throw "No VM subdirectory found in build path: $BuildPath"
}

$vhdDir = Join-Path $vmSubDir.FullName "Virtual Hard Disks"
if (-not (Test-Path $vhdDir)) {
    throw "Virtual Hard Disks directory not found in VM subdirectory: $($vmSubDir.FullName)"
}

# Check for VHD and VHDX files
$vhdFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhd"
$vhdxFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhdx"
$totalFiles = $vhdFiles.Count + $vhdxFiles.Count

if ($totalFiles -eq 0) {
    throw "No VHD or VHDX files found in: $vhdDir"
}

Write-Host "Found $($vhdFiles.Count) VHD file(s) and $($vhdxFiles.Count) VHDX file(s)"
foreach ($vhd in $vhdFiles) {
    Write-Host "  VHD: $($vhd.Name)"
}
foreach ($vhdx in $vhdxFiles) {
    Write-Host "  VHDX: $($vhdx.Name)"
}

# Convert all VHDX files to VHD format if needed
if ($vhdxFiles.Count -gt 0) {
    Write-Host "`nConverting VHDX files to VHD format..."
    foreach ($vhdxFile in $vhdxFiles) {
        $vhdPath = [System.IO.Path]::ChangeExtension($vhdxFile.FullName, '.vhd')
        Write-Host "Converting: $($vhdxFile.Name) -> $([System.IO.Path]::GetFileName($vhdPath))"

        try {
            Convert-VHD -Path $vhdxFile.FullName -DestinationPath $vhdPath -VHDType Dynamic
            Write-Host "  Converted successfully"
        } catch {
            throw "Failed to convert VHDX to VHD: $($vhdxFile.Name) - $_"
        }
    }
} else {
    Write-Host "`nAll files are already in VHD format"
}

# Process all VHD files: convert to Fixed and ensure MiB alignment (idempotent operations)
Write-Host "`nProcessing all VHD files for Azure compatibility..."
$allVhdFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhd"
$mib = 1048576  # 1 MiB = 1048576 bytes

foreach ($vhdFile in $allVhdFiles) {
    $fileName = $vhdFile.Name
    Write-Host "`nProcessing: $fileName"

    $vhd = Get-VHD -Path $vhdFile.FullName
    $currentVirtualSize = $vhd.Size
    $currentFileSize = (Get-Item -Path $vhdFile.FullName).Length

    Write-Host "  Virtual size: $currentVirtualSize bytes ($([Math]::Round($currentVirtualSize / 1GB, 2)) GB)"
    Write-Host "  File size: $currentFileSize bytes"
    Write-Host "  Type: $($vhd.VhdType)"

    $needsProcessing = $false

    # Check MiB alignment
    $currentMiB = $currentVirtualSize / $mib
    if ($currentMiB -ne [Math]::Floor($currentMiB)) {
        Write-Host "  Virtual size not MiB-aligned, resizing..."
        $alignedMiB = [Math]::Ceiling($currentMiB)
        $alignedVirtualSize = $alignedMiB * $mib

        Resize-VHD -Path $vhdFile.FullName -SizeBytes $alignedVirtualSize
        Write-Host "  Resized to $alignedVirtualSize bytes ($alignedMiB MiB)"
        $needsProcessing = $true
    }

    # Convert to Fixed if needed (replace original file)
    $vhd = Get-VHD -Path $vhdFile.FullName
    if ($vhd.VhdType -eq 'Dynamic') {
        Write-Host "  Converting to Fixed type (replacing original)..."
        $fileExtension = [System.IO.Path]::GetExtension($vhdFile.FullName)
        $tempFixedPath = $vhdFile.FullName -replace "$fileExtension$", "_fixed$fileExtension"

        Convert-VHD -Path $vhdFile.FullName -DestinationPath $tempFixedPath -VHDType Fixed

        # Replace original with fixed version
        Remove-Item -Path $vhdFile.FullName -Force
        Move-Item -Path $tempFixedPath -Destination $vhdFile.FullName -Force

        Write-Host "  Converted to Fixed type and replaced original"
        $needsProcessing = $true
    } else {
        Write-Host "  Already Fixed type"
    }

    Write-Host "  [OK] File ready for Azure upload"
}

Write-Host "`nAll VHD files processed and ready for upload"

# Create storage container if it doesn't exist
Write-Host "`nEnsuring storage container exists..."

# Capture stderr and stdout separately to get full error details
$tempErrorFile = [System.IO.Path]::GetTempFileName()
$tempOutputFile = [System.IO.Path]::GetTempFileName()

try {
    # Run az command and capture output to files
    Start-Process -FilePath "az" -ArgumentList "storage","container","create","--account-name",$StorageAccount,"--name",$ContainerName,"--output","json" -NoNewWindow -Wait -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile
    $createExitCode = $LASTEXITCODE

    $stdOutput = Get-Content $tempOutputFile -Raw -ErrorAction SilentlyContinue
    $stdError = Get-Content $tempErrorFile -Raw -ErrorAction SilentlyContinue

    Write-Host "Command exit code: $createExitCode"
    if ($stdOutput) { Write-Host "Output: $stdOutput" }
    if ($stdError) { Write-Host "Error: $stdError" }

    if ($createExitCode -ne 0) {
        # Container creation failed, check if it already exists
        Write-Host "Container creation failed, checking if it exists..."

        # Clear temp files
        Clear-Content $tempOutputFile -ErrorAction SilentlyContinue
        Clear-Content $tempErrorFile -ErrorAction SilentlyContinue

        Start-Process -FilePath "az" -ArgumentList "storage","container","exists","--account-name",$StorageAccount,"--name",$ContainerName,"--output","tsv" -NoNewWindow -Wait -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile
        $existsExitCode = $LASTEXITCODE

        $existsOutput = Get-Content $tempOutputFile -Raw -ErrorAction SilentlyContinue
        $existsError = Get-Content $tempErrorFile -Raw -ErrorAction SilentlyContinue

        if ($existsExitCode -eq 0 -and $existsOutput.Trim() -eq "true") {
            Write-Host "Container '$ContainerName' already exists"
        } else {
            throw "Failed to create or verify container '$ContainerName'. Create error: $stdError. Exists error: $existsError"
        }
    } else {
        Write-Host "Container '$ContainerName' ready"
    }
} finally {
    # Clean up temp files
    Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue
    Remove-Item $tempOutputFile -Force -ErrorAction SilentlyContinue
}

# Generate container URL and target path
$containerUrl = "https://$StorageAccount.blob.core.windows.net/$ContainerName"
$targetPath = "$containerUrl/$BlobPrefix/"
Write-Host "Target container: $containerUrl"
Write-Host "Target path: $BlobPrefix/"

# Upload VHD directory to blob storage
Write-Host "`nUploading VHD directory to blob storage..."
Write-Host "This may take a while depending on VHD size and connection speed..."

try {
    # Generate SAS token for container upload (8 hours for large uploads)
    Write-Host "Generating container SAS token for upload..."
    $expiryTime = (Get-Date).AddHours(8).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $sasToken = az storage container generate-sas --account-name $StorageAccount --name $ContainerName --permissions rwcdl --expiry $expiryTime --output tsv

    if ($LASTEXITCODE -ne 0 -or -not $sasToken) {
        throw "Failed to generate SAS token for container upload"
    }

    Write-Host "Container SAS token generated successfully"

    $destinationUrl = "$containerUrl/$BlobPrefix/?$sasToken"
    $jobIdFile = Join-Path $BuildPath "azcopy-job-id.txt"

    # Check for existing job to resume first
    if (Test-Path $jobIdFile) {
        $existingJobId = Get-Content $jobIdFile -Raw -ErrorAction SilentlyContinue
        if ($existingJobId) {
            Write-Host "`nFound existing upload job: $($existingJobId.Trim())"

            # Check job status first
            Write-Host "Checking job status..."
            $jobStatusOutput = & $azcopyPath jobs show $existingJobId.Trim() 2>&1
            $jobStatusExitCode = $LASTEXITCODE

            if ($jobStatusExitCode -eq 0) {
                $jobStatus = "Unknown"
                foreach ($line in $jobStatusOutput) {
                    if ($line -match "Final Job Status:\s*(.+)") {
                        $jobStatus = $matches[1].Trim()
                        break
                    }
                }

                Write-Host "Job status: $jobStatus"

                if ($jobStatus -eq "Failed") {
                    Write-Host "Job has failed status and cannot be resumed. Cleaning up and starting fresh..."
                    & $azcopyPath jobs remove $existingJobId.Trim() 2>&1 | Out-Null
                    Remove-Item $jobIdFile -Force -ErrorAction SilentlyContinue
                    Write-Host "Removed failed job and will start new upload"
                } elseif ($jobStatus -eq "InProgress") {
                    Write-Host "Attempting to resume in-progress upload..."
                    # Use Storage Explorer environment for resume
                    $env:AZCOPY_CONCURRENCY_VALUE = ""
                    $env:AZCOPY_CRED_TYPE = ""
                    $resumeOutput = & $azcopyPath jobs resume $existingJobId.Trim() --destination-sas $sasToken 2>&1
                    $resumeExitCode = $LASTEXITCODE
                    # Reset environment
                    $env:AZCOPY_CONCURRENCY_VALUE = "AUTO"
                    $env:AZCOPY_CRED_TYPE = "Anonymous"

                    Write-Host "Resume exit code: $resumeExitCode"
                    if ($resumeOutput -and $resumeOutput.Count -gt 0) {
                        Write-Host "Resume output:"
                        $resumeOutput | ForEach-Object { Write-Host "  $_" }
                    }

                    if ($resumeExitCode -eq 0) {
                        Write-Host "Previous upload resumed and completed successfully!"
                        Remove-Item $jobIdFile -Force -ErrorAction SilentlyContinue
                        Write-Host "VHD directory upload completed successfully"
                        return
                    } else {
                        Write-Host "Failed to resume in-progress job (exit code: $resumeExitCode)"
                        Write-Host "This may be due to expired SAS token or network issues."
                        Write-Host "Starting fresh upload instead..."
                        & $azcopyPath jobs remove $existingJobId.Trim() 2>&1 | Out-Null
                        Remove-Item $jobIdFile -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Host "Job status '$jobStatus' - cleaning up and starting fresh..."
                    & $azcopyPath jobs remove $existingJobId.Trim() 2>&1 | Out-Null
                    Remove-Item $jobIdFile -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "Could not check job status (exit code: $jobStatusExitCode) - starting fresh..."
                Remove-Item $jobIdFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Upload VHD files individually to avoid deep directory structure
    Write-Host "Uploading VHD files with network cap: $CapMbps Mbps"
    Write-Host "Source: $vhdDir"
    Write-Host "Target: $BlobPrefix/"

    # Get all VHD files
    $vhdFiles = Get-ChildItem -Path $vhdDir -Filter "*.vhd"
    if ($vhdFiles.Count -eq 0) {
        throw "No VHD files found in directory: $vhdDir"
    }

    # Upload VHD files with wildcard pattern
    $sourcePattern = Join-Path $vhdDir "*.vhd"

    # Configure AzCopy environment like Storage Explorer
    $env:AZCOPY_CONCURRENCY_VALUE = ""
    $env:AZCOPY_CRED_TYPE = ""

    # Capture azcopy output to extract job ID
    Write-Host "Running AzCopy command like Storage Explorer..."
    Write-Host "Source: $sourcePattern"
    Write-Host "Destination: $destinationUrl"
    Write-Host "Bandwidth cap: $CapMbps Mbps"

    # Ensure PowerShell shows progress bars
    $originalProgressPreference = $ProgressPreference
    $ProgressPreference = "Continue"

    # Use Storage Explorer's exact approach with ALL parameters
    # Use real-time output technique to show progress like Storage Explorer
    Write-Host "Starting upload with real-time progress using Storage Explorer settings..."
    Write-Host "Progress preference: $ProgressPreference"

    try {
        # Run AzCopy with direct console output for full progress display
        Write-Host "Running AzCopy with Storage Explorer settings and full progress display..."
        & $azcopyPath copy $sourcePattern $destinationUrl --overwrite=prompt --from-to=LocalBlob --blob-type Detect --follow-symlinks --cap-mbps $CapMbps --check-length=true --put-md5 --disable-auto-decoding=false --recursive --log-level=INFO
        $uploadExitCode = $LASTEXITCODE

        # Get the latest job ID after completion (Method 1)
        if ($uploadExitCode -eq 0) {
            Write-Host "`nCapturing job ID for future reference..."
            $jobsList = & $azcopyPath jobs list --output-type=json 2>$null
            if ($jobsList) {
                try {
                    $latestJob = ($jobsList | ConvertFrom-Json)[0]  # Most recent job
                    $jobId = $latestJob.JobId
                    if ($jobId) {
                        Write-Host "Latest job ID: $jobId"
                        Set-Content -Path $jobIdFile -Value $jobId
                        Write-Host "Job ID saved to: $jobIdFile"
                    }
                } catch {
                    Write-Host "Note: Could not parse job ID from AzCopy jobs list (this is not critical)"
                }
            }
        }
    } finally {
        # Restore original progress preference
        $ProgressPreference = $originalProgressPreference
    }

    # Reset environment like Storage Explorer
    $env:AZCOPY_CONCURRENCY_VALUE = "AUTO"
    $env:AZCOPY_CRED_TYPE = "Anonymous"

    if ($uploadExitCode -eq 0) {
        Write-Host "Upload completed successfully!"
        # Clean up any old job ID files
        if (Test-Path $jobIdFile) {
            Remove-Item $jobIdFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "Upload failed with exit code: $uploadExitCode"
        throw "VHD directory upload failed. Using Storage Explorer approach with --blob-type Detect should be more reliable."
    }

    Write-Host "VHD directory upload completed successfully"

} catch {
    throw "Azure blob upload failed: $_"

} finally {
    # Clean up temporary files if any exist
    Get-ChildItem -Path $vhdDir -Filter "*_fixed.vhd*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Cleaning up temporary file: $($_.Name)"
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==========================================="
Write-Host "Azure VHD directory upload completed successfully!"
Write-Host "Storage Account: $StorageAccount"
Write-Host "Container: $ContainerName"
Write-Host "Blob Prefix: $BlobPrefix"
Write-Host "Container URL: $containerUrl"
Write-Host ""
Write-Host "VHD files uploaded to: $targetPath"
Write-Host ""
Write-Host "To create a managed disk from uploaded VHDs, use:"
Write-Host "az disk create --resource-group <RG> --name <DISK_NAME> --source <VHD_BLOB_URL>"
Write-Host ""
Write-Host "To create a managed image from uploaded VHDs, use:"
Write-Host "az image create --resource-group <RG> --name <IMAGE_NAME> --source <VHD_BLOB_URL> --os-type <OS_TYPE>"
Write-Host "==========================================="

exit 0