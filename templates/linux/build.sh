#!/usr/bin/env bash
# build.sh — cloud-image-customize Linux build flow.
#
# Thin orchestrator. Reads shared helpers from lib/common.sh, then sources
# the family module (lib/ubuntu.sh or lib/rhel.sh) which provides hooks for
# image URL/checksum, resize, and family-specific virt-customize args.
#
# Output layout:
#   <output-dir>/<template>-stage1/
#     metadata.json
#     catlet.yaml
#     kvm/amd64/sda.qcow2     (default kernel, generic cloud datasource list)
#     hyperv/amd64/sda.vhdx   (Ubuntu: linux-azure + walinuxagent; RHEL: same as qcow2)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
FILES_DIR="$SCRIPT_DIR/files"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/common.sh"
parse_args "$@"

# Dispatch by template name. Family module must provide:
#   <fam>_init, <fam>_parse_checksum_line, <fam>_resize_image,
#   <fam>_common_vc_args, <fam>_pkg_clean_vc_args, <fam>_hyperv_vc_args
case "$TEMPLATE_NAME" in
  ubuntu-*)
    FAMILY=ubuntu;    source "$LIB_DIR/ubuntu.sh" ;;
  almalinux-*)
    FAMILY=rhel;      source "$LIB_DIR/rhel.sh" ;;
  oracle-*)
    die "oracle-* not supported here; use the packer flow at templates/rhel-compatible/" ;;
  *)
    die "unsupported template: $TEMPLATE_NAME" ;;
esac

${FAMILY}_init
init_workdir
setup_logging
ensure_libguestfs_backend

# ---------- Stage A: fetch sources ----------
fetch_cloud_image
${FAMILY}_resize_image
fetch_eryph_guest_services

# ---------- Stage B: common pass (yields kvm/amd64/sda.qcow2) ----------
log_step "[4/7] virt-customize: common pass (kvm-flavored)"
reset_vc_args
${FAMILY}_common_vc_args        # family-specific: resize-fs, pkg ops, GRUB
common_provision_vc_args        # shared: eryph-gs, cloud-init drops (kvm flavor)
common_cleanup_vc_args          # shared: machine-id, ssh keys, log truncation
${FAMILY}_pkg_clean_vc_args     # family-specific: apt clean / dnf clean
virt-customize -v -x -a "$WORK_IMG" --memsize 1024 --smp 2 --network "${VC_ARGS[@]}"

# ---------- Stage C: place stage1 + emit qcow2 ----------
STAGE_DIR="$OUTPUT_DIR/${TEMPLATE_NAME}-stage1"
KVM_DIR="$STAGE_DIR/kvm/amd64"
HV_DIR="$STAGE_DIR/hyperv/amd64"
mkdir -p "$STAGE_DIR"
emit_qcow2

# ---------- Stage D: optional hyper-v variant ----------
if [[ "$CONVERT_VHDX" == "true" ]]; then
  HV_IMG="$WORK_DIR/sda-hv.qcow2"
  cp --reflink=auto "$WORK_IMG" "$HV_IMG"

  reset_vc_args
  ${FAMILY}_hyperv_vc_args      # family-specific additions for hyper-v variant
  if [[ ${#VC_ARGS[@]} -gt 0 ]]; then
    log_step "[6/7] virt-customize: hyper-v pass ($FAMILY-specific additions)"
    virt-customize -v -x -a "$HV_IMG" --memsize 1024 --smp 2 --network "${VC_ARGS[@]}"
  else
    log_step "[6/7] hyper-v pass: no $FAMILY-specific additions; reusing common image"
  fi
  emit_vhdx "$HV_IMG"
fi

# ---------- Stage E: metadata + catlet defaults ----------
emit_metadata_and_catlet

log_step "Done. Output in $STAGE_DIR:"
find "$STAGE_DIR" -maxdepth 4 -ls
