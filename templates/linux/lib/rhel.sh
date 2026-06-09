# rhel.sh — Red Hat-family hooks for the cloud-image-customize flow.
#
# AlmaLinux GenericCloud only for now (Rocky/CentOS-Stream would slot in here).
# Source: https://repo.almalinux.org/almalinux/<major>/cloud/x86_64/images/
#
# Single variant: the default kernel handles both Hyper-V and KVM (RHEL 8+
# ships hv_* drivers in-tree, virtio drivers too). Same image is emitted as
# both qcow2 (kvm/amd64) and vhdx (hyperv/amd64) — only the container differs.

VERSION=""

rhel_init() {
  case "$TEMPLATE_NAME" in
    almalinux-8|almalinux-9|almalinux-10)
      VERSION="${TEMPLATE_NAME#almalinux-}"
      ;;
    *) die "rhel_init called with unsupported template: $TEMPLATE_NAME" ;;
  esac
  IMAGE_FILE="AlmaLinux-${VERSION}-GenericCloud-latest.x86_64.qcow2"
  IMAGE_URL="https://repo.almalinux.org/almalinux/${VERSION}/cloud/x86_64/images/${IMAGE_FILE}"
  SUMS_URL="https://repo.almalinux.org/almalinux/${VERSION}/cloud/x86_64/images/CHECKSUM"
  CACHE_FILE_PREFIX="almalinux-${VERSION}"
}

# AlmaLinux CHECKSUM uses GNU coreutils format: "<hash>  <filename>".
rhel_parse_checksum_line() {
  awk -v f="${IMAGE_FILE}" '$2==f {print $1}'
}

# GenericCloud already ships at 10 GiB virtual; nothing to grow.
rhel_resize_image() { :; }

# Pre-eryph-gs RHEL ops: optional dist upgrade. The image is already
# cloud-init-ready, serial-console-enabled in GRUB, and ships hv_*/virtio
# drivers in the default kernel.
rhel_common_vc_args() {
  if [[ "$DIST_UPGRADE" == "true" ]]; then
    VC_ARGS+=( --run-command 'dnf -y upgrade' )
  fi
  # Hyper-V integration daemons. The AlmaLinux GenericCloud image ships the
  # hv_* kernel modules but NOT the userspace daemons. hypervkvpd in particular
  # creates /var/lib/hyperv/.kvp_pool_* and drives the KVP data-exchange channel
  # that eryph-guest-services (and cloud-init's hyperv reporting) rely on -
  # without it egs-service crashes on startup and never reports "available".
  # (The old packer flow installed these in scripts/hyperv.sh; the cloud-image
  # flow must do the same.) The daemons auto-start via udev when the matching
  # vmbus device appears on boot; enabling is a harmless belt-and-suspenders.
  # hyperv-daemons: hypervkvpd creates /var/lib/hyperv/.kvp_pool_* and drives the
  # KVP channel egs-service + cloud-init reporting use (auto-starts via udev on
  # boot). libicu: required by the .NET-based egs-service; the AlmaLinux 8
  # GenericCloud image does not ship it, so egs-service aborts at startup with a
  # "valid ICU package" FailFast. (The old packer flow installed both.)
  VC_ARGS+=(
    --install hyperv-daemons,libicu
    --run-command 'systemctl enable hypervkvpd.service hypervvssd.service hypervfcopyd.service 2>/dev/null || true'
  )
  # Force legacy "eth0" interface naming. eryph attaches the NIC as eth0; with
  # RHEL's predictable names ( enX/ens..) the base-OS validation and eryph's
  # eth0-based network-config would not match. grubby updates the installed
  # kernel's BLS entry now; the /etc/default/grub edit covers future kernels.
  # Mirrors ubuntu.sh and the old packer scripts/hyperv.sh.
  VC_ARGS+=(
    --run-command 'grubby --update-kernel=ALL --args="net.ifnames=0 biosdevname=0"'
    --run-command 'grep -q "net.ifnames=0" /etc/default/grub || sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"net.ifnames=0 biosdevname=0 /" /etc/default/grub'
  )
}

# Terminal cleanup runs after common_cleanup_vc_args (i.e. after the eryph files
# are in place).
#
# SELinux: AlmaLinux is enforcing, and virt-customize copy-in/upload leaves the
# eryph files unlabeled_t, so systemd cannot exec the egs binary
# (status=203/EXEC) and EGS never comes up. The label cannot be fixed offline:
# restorecon/setfiles and even a raw security.selinux xattr write all fail in
# the libguestfs appliance (it boots selinux=0, so there is no SELinux LSM to
# accept the label), and --selinux-relabel just defers a slow full-FS relabel to
# first boot via /.autorelabel. Instead we install eryph-selinux-relabel.service:
# a oneshot that runs `restorecon -R /opt/eryph` once on first boot (when the
# kernel SELinux policy is loaded), ordered before eryph-guest-services. The
# tree is tiny so this costs only a few ms - boot stays fast and SELinux stays
# enforcing.
rhel_pkg_clean_vc_args() {
  VC_ARGS+=(
    --upload "$FILES_DIR/eryph-selinux-relabel.service:/etc/systemd/system/eryph-selinux-relabel.service"
    --link '/etc/systemd/system/eryph-selinux-relabel.service:/etc/systemd/system/multi-user.target.wants/eryph-selinux-relabel.service'
    --run-command 'dnf clean all'
  )
}

# No kernel swap for RHEL — but the cloud-init datasource list still differs
# per variant: hyperv variant gets the Azure-flavored drop-in. build.sh runs
# a second virt-customize pass when VC_ARGS is non-empty.
rhel_hyperv_vc_args() {
  VC_ARGS+=( --upload "$FILES_DIR/91-eryph-hyperv.cfg:/etc/cloud/cloud.cfg.d/91-eryph.cfg" )

  # Azure enablement: these images are also published to Azure, where the
  # platform expects the Azure Linux Agent. waagent.conf disables waagent's own
  # provisioning and defers to cloud-init (same waagent.conf as the ubuntu
  # variant). Gated by --no-walinuxagent like ubuntu. The package comes from the
  # distro repos and is correctly labeled by dnf.
  if [[ "$WALINUXAGENT" == "true" ]]; then
    VC_ARGS+=(
      --install WALinuxAgent
      --upload "$FILES_DIR/waagent.conf:/etc/waagent.conf"
      --run-command 'systemctl enable waagent.service 2>/dev/null || true'
      # Gate the agent to Azure-only (see waagent-azure-only.conf). On AlmaLinux 8
      # (systemd 239) ExecCondition is ignored and the agent runs as before;
      # Logs.Console=n in waagent.conf keeps the console quiet in that case.
      --mkdir /etc/systemd/system/waagent.service.d
      --upload "$FILES_DIR/waagent-azure-only.conf:/etc/systemd/system/waagent.service.d/10-azure-only.conf"
    )
  fi
}
