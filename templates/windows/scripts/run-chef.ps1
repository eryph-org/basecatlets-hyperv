param(
    [string]$RunList = $env:RUNLIST,
    [string]$CincVersion = "17",  # Use Cinc 17 instead of broken Chef community installer
    [string]$CookbookPath = "C:\packer\cookbooks",
    [string]$ConfigPath = "C:\packer"
)

if (-not $RunList) {
    Write-Error "RunList parameter is required. Set RUNLIST environment variable or pass -RunList parameter."
    exit 1
}

$ErrorActionPreference = "Stop"

# Create directories
New-Item -ItemType Directory -Force -Path $ConfigPath | Out-Null
New-Item -ItemType Directory -Force -Path $CookbookPath | Out-Null

# Check if Cinc is already installed
$cincInstalled = $false
try {
    $existingVersion = & cinc-solo --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Cinc is already installed: $existingVersion"
        $cincInstalled = $true
    }
} catch {
    # Cinc not found, continue with installation
}

if (-not $cincInstalled) {

    # Enable TLS 1.2 for secure downloads
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    try {
        Write-Output "Downloading and installing Cinc $CincVersion using omnibus installer..."

        # Download and execute the Cinc omnibus install script
        $installScript = Invoke-WebRequest -Uri "https://omnitruck.cinc.sh/install.ps1" -UseBasicParsing | Select-Object -ExpandProperty Content
        Invoke-Expression $installScript

        # Install Cinc
        Write-Output "Installing Cinc version $CincVersion..."
        install -project cinc -version $CincVersion

        Write-Output "Cinc installation completed"

    } catch {
        Write-Error "Failed to install Cinc: $($_.Exception.Message)"
        exit 1
    }
}

# Add Cinc to PATH for this session (in case it's not already there)
$env:PATH = "$env:PATH;C:\cinc-project\cinc\bin;C:\cinc-project\cinc\embedded\bin"

# Verify Cinc installation
try {
    $cincVersion = & cinc-solo --version
    Write-Output "Cinc installed successfully: $cincVersion"
} catch {
    Write-Error "Cinc installation verification failed: $($_.Exception.Message)"
    exit 1
}

# Create solo.rb configuration
$soloRbContent = @"
cookbook_path ['$($CookbookPath -replace '\\', '/')']
file_cache_path '$($ConfigPath -replace '\\', '/')/cache'
"@

$soloRbPath = "$ConfigPath\solo.rb"
$soloRbContent | Out-File -FilePath $soloRbPath -Encoding UTF8

Write-Output "Created solo.rb configuration at $soloRbPath"

# Create JSON attributes file with run list
$runListArray = $RunList -split ',' | ForEach-Object { "`"$($_.Trim())`"" }
$attributesContent = @"
{
    "run_list": [$($runListArray -join ', ')]
}
"@

$attributesPath = "$ConfigPath\attributes.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($attributesPath, $attributesContent, $utf8NoBom)

Write-Output "Created attributes file at $attributesPath with run list: $RunList"

# Run cinc-solo
try {
    Write-Output "Running cinc-solo..."
    & cinc-solo --config $soloRbPath --json-attributes $attributesPath --log_level info --no-color
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cinc-solo execution failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    Write-Output "cinc-solo completed successfully"
    
} catch {
    Write-Error "Failed to execute cinc-solo: $($_.Exception.Message)"
    exit 1
}