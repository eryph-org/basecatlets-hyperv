#!/bin/bash
set -euo pipefail

# Create RPM build directory structure
echo "Setting up RPM build environment..."
mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Function to fetch latest version from releases API
fetch_latest_version() {
    echo "Fetching eryph guest services release information..."

    # Download release information
    curl -s https://releases.dbosoft.eu/eryph/guest-services/index.json > /tmp/releases.json

    # Parse JSON to get latest stable version, fallback to latest version
    VERSION=$(python3 -c "
import json
with open('/tmp/releases.json') as f:
    data = json.load(f)
print(data.get('stableVersion', data['latestVersion']))
" 2>/dev/null || echo "latest")

    echo "Target version: $VERSION"

    # Get download URL for Linux amd64
    DOWNLOAD_URL=$(python3 -c "
import json
with open('/tmp/releases.json') as f:
    data = json.load(f)
version = '$VERSION'
if version == 'latest':
    version = data['latestVersion']
version_info = data['versions'][version]
for file_info in version_info['files']:
    if (file_info['filename'].startswith('egs_') and
        file_info.get('os') == 'linux' and
        file_info.get('arch') == 'amd64'):
        print(file_info['url'])
        break
" 2>/dev/null || echo "")

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "ERROR: Could not find suitable Linux amd64 release"
        exit 1
    fi

    echo "Download URL: $DOWNLOAD_URL"
    export EGS_VERSION="$VERSION"
    export EGS_DOWNLOAD_URL="$DOWNLOAD_URL"
}

# Fetch version information
fetch_latest_version

# Download eryph guest services
echo "Downloading eryph guest services..."
curl -L "$EGS_DOWNLOAD_URL" -o ~/rpmbuild/SOURCES/egs-linux.tar.gz

# Verify download
if [ ! -f ~/rpmbuild/SOURCES/egs-linux.tar.gz ]; then
    echo "ERROR: Failed to download eryph guest services"
    exit 1
fi

# Extract to check structure
echo "Verifying package structure..."
cd /tmp
tar -tf ~/rpmbuild/SOURCES/egs-linux.tar.gz | head -10
