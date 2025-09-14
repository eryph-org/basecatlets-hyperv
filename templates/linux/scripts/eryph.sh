#!/usr/bin/env python3

import json
import os
import re
import subprocess
import urllib.request
import tarfile

def install_eryph_guest_services():
    download_url = ''
    if not download_url:
        requested_version = 'latest'
        version = requested_version
        
        print("Fetching eryph guest services release information...")
        with urllib.request.urlopen('https://releases.dbosoft.eu/eryph/guest-services/index.json') as response:
            response_json = response.read().decode('utf-8')
            product_info = json.loads(response_json)
            
            if version == 'latest':
                version = product_info.get('stableVersion')
                if not version:
                    version = product_info['latestVersion']

            if version == 'prerelease':
                version = product_info['latestVersion']
            
            version_info = product_info['versions'].get(version)
            if not version_info:
                raise Exception(f"Version {requested_version} does not exist")

            file_info = next((f for f in version_info['files'] 
                if f['filename'].startswith('egs_') 
                and 'os' in f 
                and 'arch' in f 
                and f['os'] == 'linux' 
                and f['arch'] == 'amd64'), None)
            if not file_info:
                raise Exception(f"No suitable Linux amd64 file found for version {version}")
            download_url = file_info['url']
            
            print(f"Downloading eryph guest services from {download_url}")
            urllib.request.urlretrieve(download_url, 'egs-linux.tar.gz')
            
            install_path = '/opt/eryph/guest-services'

            print(f"Installing eryph guest services to {install_path}")
            os.makedirs(install_path, exist_ok=True)
            with tarfile.open('egs-linux.tar.gz', 'r:gz') as tar:
                tar.extractall(path=install_path)
            os.remove('egs-linux.tar.gz')
            
            print("Creating systemd service file")
            service_content = """[Unit]
Description=eryph guest services

[Service]
Type=notify
ExecStart=/opt/eryph/guest-services/bin/egs-service
Environment="HOME=/root"
Environment="TERM=xterm"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
"""
            with open('/etc/systemd/system/eryph-guest-services.service', 'w') as f:
                f.write(service_content)
            
            print("Configuring and starting eryph guest services")
            subprocess.run(['systemctl', 'daemon-reload'], check=True)
            subprocess.run(['systemctl', 'enable', 'eryph-guest-services.service'], check=True)
            subprocess.run(['systemctl', 'start', 'eryph-guest-services.service'], check=True)
            
            print("eryph guest services installation completed successfully")

if __name__ == '__main__':
    try:
        install_eryph_guest_services()
    except Exception as e:
        print(f"Error installing eryph guest services: {e}")
        exit(1)