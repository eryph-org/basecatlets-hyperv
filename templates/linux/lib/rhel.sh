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
}

# Terminal cleanup runs after common_cleanup_vc_args.
rhel_pkg_clean_vc_args() {
  VC_ARGS+=( --run-command 'dnf clean all' )
}

# No kernel swap for RHEL — but the cloud-init datasource list still differs
# per variant: hyperv variant gets the Azure-flavored drop-in. build.sh runs
# a second virt-customize pass when VC_ARGS is non-empty.
rhel_hyperv_vc_args() {
  VC_ARGS+=( --upload "$FILES_DIR/91-eryph-hyperv.cfg:/etc/cloud/cloud.cfg.d/91-eryph.cfg" )
}
