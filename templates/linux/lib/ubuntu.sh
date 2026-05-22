# ubuntu.sh — Ubuntu family hooks for the cloud-image-customize flow.
#
# Source of upstream minimal cloud images:
#   https://cloud-images.ubuntu.com/minimal/releases/<codename>/release/
#
# Two variants:
#   - qcow2 (kvm/amd64): default kernel from the cloud image, no walinuxagent
#   - vhdx  (hyperv/amd64): linux-azure + walinuxagent grafted on a clone

# Set by ubuntu_init.
CODENAME=""
VERSION=""

ubuntu_init() {
  case "$TEMPLATE_NAME" in
    ubuntu-20.04) CODENAME=focal;  VERSION=20.04 ;;
    ubuntu-22.04) CODENAME=jammy;  VERSION=22.04 ;;
    ubuntu-24.04) CODENAME=noble;  VERSION=24.04 ;;
    ubuntu-25.04) CODENAME=plucky; VERSION=25.04 ;;
    *) die "ubuntu_init called with unsupported template: $TEMPLATE_NAME" ;;
  esac
  IMAGE_FILE="ubuntu-${VERSION}-minimal-cloudimg-amd64.img"
  IMAGE_URL="https://cloud-images.ubuntu.com/minimal/releases/${CODENAME}/release/${IMAGE_FILE}"
  SUMS_URL="https://cloud-images.ubuntu.com/minimal/releases/${CODENAME}/release/SHA256SUMS"
  CACHE_FILE_PREFIX="${CODENAME}-min"
}

# Ubuntu SHA256SUMS line format: "<hash> *<filename>".
ubuntu_parse_checksum_line() {
  awk -v f="*${IMAGE_FILE}" '$2==f {print $1}'
}

# Ubuntu minimal is 2.2 GiB virtual; grow to 10 GiB before any heavy install.
# growpart + resize2fs run inside the appliance as the first VC args.
ubuntu_resize_image() {
  log_step "[3.1] Resize work image to 10G (Ubuntu minimal grows)"
  qemu-img resize "$WORK_IMG" 10G
}

# Pre-eryph-gs Ubuntu virt-customize ops: grow rootfs, install qemu-guest-agent,
# remove auto-update machinery, patch GRUB for eryph's eth0 naming.
ubuntu_common_vc_args() {
  VC_ARGS+=(
    --run-command 'growpart /dev/sda 1'
    --run-command 'resize2fs /dev/sda1'
    # qemu-guest-agent: tiny, idles on Hyper-V (no virtio-serial), used on KVM.
    --install qemu-guest-agent
    --uninstall unattended-upgrades,ubuntu-release-upgrader-core
    --run-command 'sed -i "s/^Prompt=.*/Prompt=never/" /etc/update-manager/release-upgrades 2>/dev/null || true'
    --run-command 'systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true'
    --run-command 'systemctl mask apt-daily.service apt-daily-upgrade.service 2>/dev/null || true'
  )
  if [[ "$DIST_UPGRADE" == "true" ]]; then VC_ARGS+=( --update ); fi
  VC_ARGS+=(
    --run-command 'sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1 console=ttyS0 net.ifnames=0 biosdevname=0\"|" /etc/default/grub'
    --run-command 'update-grub'
  )
}

# Final apt cleanup. Runs after common_cleanup_vc_args.
ubuntu_pkg_clean_vc_args() {
  VC_ARGS+=(
    --run-command 'apt-get -y autoremove --purge'
    --run-command 'apt-get clean'
  )
}

# Hyper-V variant ops: swap to linux-azure, optional walinuxagent, Azure-flavored
# cloud-init datasource. Runs on a clone of the common-pass output.
ubuntu_hyperv_vc_args() {
  # Replace KVM-flavored datasource drop-in with the Hyper-V/Azure one.
  VC_ARGS+=( --upload "$FILES_DIR/91-eryph-hyperv.cfg:/etc/cloud/cloud.cfg.d/91-eryph.cfg" )

  case "$KERNEL" in
    azure)
      VC_ARGS+=( --install linux-azure )
      VC_ARGS+=( --run-command 'apt-get -y remove --purge linux-generic linux-image-generic linux-headers-generic linux-virtual linux-image-virtual linux-headers-virtual || true' )
      ;;
    generic|default) ;;
    *) die "bad --kernel value: $KERNEL" ;;
  esac

  if [[ "$WALINUXAGENT" == "true" ]]; then
    VC_ARGS+=(
      --install walinuxagent,cloud-guest-utils
      --upload "$FILES_DIR/waagent.conf:/etc/waagent.conf"
    )
  fi

  VC_ARGS+=(
    --run-command 'apt-get -y autoremove --purge'
    --run-command 'apt-get clean'
  )
}
