Name:           eryph-guest-services
Version:        %{_version}
Release:        1%{?dist}
Summary:        Eryph Guest Services for Hyper-V virtualization

License:        Apache-2.0
URL:            https://github.com/eryph-org/guest-services
Source0:        egs-linux.tar.gz

BuildArch:      x86_64
Requires:       systemd

%description
Guest services daemon for eryph virtualization platform. Provides communication
between the Hyper-V host and Linux guest systems for configuration management,
file transfer, and system monitoring.

%prep
%setup -q -c -n %{name}-%{version}

%build
# No build needed - pre-compiled binaries

%install
rm -rf $RPM_BUILD_ROOT

# Create installation directories
mkdir -p $RPM_BUILD_ROOT/opt/eryph/guest-services/bin
mkdir -p $RPM_BUILD_ROOT/usr/lib/systemd/system
mkdir -p $RPM_BUILD_ROOT/usr/lib/systemd/system-preset

# Install eryph guest services binaries
cp -r bin/* $RPM_BUILD_ROOT/opt/eryph/guest-services/bin/

# Create systemd service file
cat > $RPM_BUILD_ROOT/usr/lib/systemd/system/eryph-guest-services.service << 'EOF'
[Unit]
Description=eryph guest services
After=network.target

[Service]
Type=notify
ExecStart=/opt/eryph/guest-services/bin/egs-service
Environment="HOME=/root"
Environment="TERM=xterm"
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create systemd preset to auto-enable the service
cat > $RPM_BUILD_ROOT/usr/lib/systemd/system-preset/90-eryph-guest-services.preset << 'EOF'
enable eryph-guest-services.service
EOF

%files
/opt/eryph/guest-services/bin/*
/usr/lib/systemd/system/eryph-guest-services.service
/usr/lib/systemd/system-preset/90-eryph-guest-services.preset

%post
# Reload systemd and apply presets (only works outside chroot)
if [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
    systemctl preset eryph-guest-services.service || true
fi

%preun
# Stop service before uninstall (only works outside chroot)
if [ $1 -eq 0 ] && [ -d /run/systemd/system ]; then
    systemctl stop eryph-guest-services.service || true
    systemctl disable eryph-guest-services.service || true
fi

%postun
# Reload systemd after uninstall (only works outside chroot)
if [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
fi

%changelog
* Mon Sep 15 2025 Azure Linux Build System <noreply@eryph.io> - %{_version}-1
- Initial RPM package for eryph guest services
- Auto-generated during Azure Linux image build
- Includes systemd service and preset files