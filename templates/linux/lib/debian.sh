# debian.sh — Debian family hooks for the cloud-image-customize flow.
#
# Source of upstream cloud images:
#   https://cloud.debian.org/images/cloud/<codename>/latest/
#
# We build from the "genericcloud" variant (debian-<ver>-genericcloud-amd64.qcow2):
# its kernel (linux-image-cloud-amd64) is the multi-cloud kernel Debian ships to
# Azure/KVM/OpenStack and already carries the hv_* drivers, so — unlike Ubuntu —
# there is no linux-azure graft. Single image emitted as both qcow2 (kvm/amd64)
# and vhdx (hyperv/amd64); only the container differs.
#
# Debian publishes SHA512SUMS (no SHA256SUMS), so this module overrides
# CHECKSUM_CMD to sha512sum (common.sh defaults to sha256sum).

# Set by debian_init.
CODENAME=""
VERSION=""

debian_init() {
  case "$TEMPLATE_NAME" in
    debian-12) CODENAME=bookworm; VERSION=12 ;;
    debian-13) CODENAME=trixie;   VERSION=13 ;;
    *) die "debian_init called with unsupported template: $TEMPLATE_NAME" ;;
  esac
  IMAGE_FILE="debian-${VERSION}-genericcloud-amd64.qcow2"
  IMAGE_URL="https://cloud.debian.org/images/cloud/${CODENAME}/latest/${IMAGE_FILE}"
  SUMS_URL="https://cloud.debian.org/images/cloud/${CODENAME}/latest/SHA512SUMS"
  CACHE_FILE_PREFIX="debian-${VERSION}"
  CHECKSUM_CMD="sha512sum"
}

# Debian SHA512SUMS uses GNU coreutils format: "<hash>  <filename>".
debian_parse_checksum_line() {
  awk -v f="${IMAGE_FILE}" '$2==f {print $1}'
}

# Debian genericcloud ships ~3 GiB virtual; grow to 10 GiB before any install.
# growpart + resize2fs run inside the appliance as the first VC args.
debian_resize_image() {
  log_step "[3.1] Resize work image to 10G (Debian genericcloud grows)"
  qemu-img resize "$WORK_IMG" 10G
}

# Pre-eryph-gs Debian virt-customize ops: grow rootfs, install qemu-guest-agent +
# firewall, Hyper-V KVP daemons and ICU for eryph-guest-services, strip auto-update
# machinery, patch GRUB for eryph's eth0 naming.
debian_common_vc_args() {
  VC_ARGS+=(
    # qemu-guest-agent: idles on Hyper-V, used on KVM. openssh-server/ufw: the
    # base-OS validation (Debian is matched as the debian|ubuntu branch) expects
    # sshd and a firewall. cloud-guest-utils: provides growpart. hyperv-daemons:
    # hv_kvp_daemon drives the KVP channel eryph-guest-services + cloud-init
    # reporting rely on (the kernel ships the hv_* modules but not the daemons).
    --install qemu-guest-agent,openssh-server,ufw,cloud-guest-utils,hyperv-daemons
    --run-command 'growpart /dev/sda 1 || true'
    --run-command 'resize2fs /dev/sda1 || true'
    --run-command 'systemctl enable hv-kvp-daemon.service hv-vss-daemon.service hv-fcopy-daemon.service 2>/dev/null || true'
    # libicu: required by the .NET-based egs-service, which FailFasts without a
    # "valid ICU package". genericcloud does not ship it; install the highest
    # available versioned runtime (name is libicuNN, differs per release).
    --run-command 'apt-get update; pkg=$(apt-cache search --names-only "^libicu[0-9][0-9]*$" | sort -V | tail -n1 | cut -d" " -f1); if [ -n "$pkg" ]; then DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"; fi'
    # eryph's cloud-init user-data runs `useradd admin ...`; drop any stray
    # 'admin' group so useradd can create its private group. No-op when absent.
    --run-command 'groupdel admin 2>/dev/null || true'
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
debian_pkg_clean_vc_args() {
  VC_ARGS+=(
    --run-command 'apt-get -y autoremove --purge'
    --run-command 'apt-get clean'
  )
}

# Hyper-V variant: Azure-flavored cloud-init datasource drop-in + walinuxagent.
# No kernel swap — Debian's genericcloud kernel already handles Hyper-V. Like the
# ubuntu/rhel variants, the same image is Azure-publishable, so the Azure Linux
# Agent is shipped but gated to Azure-only (the ExecCondition drop-in keys on the
# Azure chassis asset tag; off-Azure, e.g. on eryph/Hyper-V, it stays inactive).
# The base-OS validation requires it on the debian|ubuntu branch. On Debian the
# package is 'waagent' (Ubuntu ships it as 'walinuxagent'), but it still installs
# the historical systemd unit 'walinuxagent.service' and /etc/waagent.conf, so
# the service/conf/drop-in paths match the Ubuntu layout. build.sh runs a second
# virt-customize pass when VC_ARGS is non-empty.
debian_hyperv_vc_args() {
  VC_ARGS+=( --upload "$FILES_DIR/91-eryph-hyperv.cfg:/etc/cloud/cloud.cfg.d/91-eryph.cfg" )

  if [[ "$WALINUXAGENT" == "true" ]]; then
    VC_ARGS+=(
      --install waagent
      --upload "$FILES_DIR/waagent.conf:/etc/waagent.conf"
      --mkdir /etc/systemd/system/walinuxagent.service.d
      --upload "$FILES_DIR/waagent-azure-only.conf:/etc/systemd/system/walinuxagent.service.d/10-azure-only.conf"
      # virt-customize runs offline, so enable the unit explicitly rather than
      # rely on the deb postinst firing (the Azure-only gate keeps it inactive
      # off-Azure). Mirrors ubuntu.sh / rhel.sh.
      --run-command 'systemctl enable walinuxagent.service 2>/dev/null || true'
    )
  fi
}
