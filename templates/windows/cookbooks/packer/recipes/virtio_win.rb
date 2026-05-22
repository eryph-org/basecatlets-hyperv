# virtio-win — KVM/QEMU paravirtualized drivers + qemu-guest-agent for Windows.
#
# Required for the qcow2/kvm-amd64 gene variant: Windows ships no virtio
# drivers, so a Hyper-V-built VHDX converted to qcow2 BSODs at boot on a VM
# configured with virtio-scsi / virtio-blk. With this MSI installed, the
# resulting image boots cleanly on both:
#   - Hyper-V (drivers idle, no virtio bus present)
#   - KVM/libvirt/Proxmox/OpenStack (drivers activate on the virtio bus)
#
# Upstream: https://fedorapeople.org/groups/virt/virtio-win/
# Package: virtio-win-gt-x64.msi (Windows Drivers, 64-bit)
# Includes: virtio-net, virtio-scsi, virtio-blk, virtio-balloon, virtio-serial,
#           virtio-rng, qemu-guest-agent.

remote_file "#{Chef::Config[:file_cache_path]}/virtio-win-gt-x64.msi" do
  source 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win-gt-x64.msi'
  action :create
end

# ADDLOCAL=ALL forces every driver component to install. The default install
# set excludes some optional drivers (e.g. virtio-rng, qemu-guest-agent) — we
# want all of them present so the qcow2 variant works in any KVM environment.
windows_package 'virtio-win-driver-installer' do
  source "#{Chef::Config[:file_cache_path]}/virtio-win-gt-x64.msi"
  installer_type :msi
  options '/quiet /norestart ADDLOCAL=ALL'
  action :install
end
