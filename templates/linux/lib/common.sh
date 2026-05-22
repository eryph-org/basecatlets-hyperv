# common.sh — shared helpers for the cloud-image-customize build flow.
#
# Sourced by build.sh. Provides:
#   - parse_args / log helpers
#   - workdir + logging setup
#   - libguestfs backend selection
#   - generic image fetch (with per-family checksum parser hook)
#   - eryph-guest-services fetch + extract
#   - shared virt-customize arg builders (provisioning, finalize)
#   - metadata.json + catlet.yaml emission
#
# Family modules (lib/ubuntu.sh, lib/rhel.sh) provide:
#   - <family>_init                 — set IMAGE_URL, SUMS_URL, image filename
#   - <family>_parse_checksum_line  — extract expected sha256 from SUMS file
#   - <family>_resize_image         — qemu-img resize the working file (or no-op)
#   - <family>_common_vc_args       — pre-eryph-gs args (resize-fs, pkg ops, GRUB)
#   - <family>_pkg_clean_vc_args    — terminal cleanup (apt clean / dnf clean)
#   - <family>_hyperv_vc_args       — additional args for the Hyper-V variant

set -euo pipefail

# ---------- logging ----------
log_info()  { echo "[$(date +%H:%M:%S)] $*"; }
log_step()  { echo; echo "==> $*"; }
log_warn()  { echo "[$(date +%H:%M:%S)] WARN: $*" >&2; }
die()       { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

# ---------- argument parsing ----------
TEMPLATE_NAME=""
OUTPUT_DIR=""
CACHE_DIR=""
KERNEL="azure"           # ubuntu hyper-v variant only
WALINUXAGENT="true"      # ubuntu hyper-v variant only
CONVERT_VHDX="false"
DIST_UPGRADE="false"

usage() {
  cat >&2 <<EOF
Usage: $0 --template <name> --output-dir <path> [options]
Templates: ubuntu-22.04, ubuntu-24.04, ubuntu-25.04,
           almalinux-8, almalinux-9, almalinux-10
EOF
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template)        TEMPLATE_NAME="$2"; shift 2 ;;
      --output-dir)      OUTPUT_DIR="$2"; shift 2 ;;
      --cache-dir)       CACHE_DIR="$2"; shift 2 ;;
      --kernel)          KERNEL="$2"; shift 2 ;;
      --no-walinuxagent) WALINUXAGENT="false"; shift ;;
      --dist-upgrade)    DIST_UPGRADE="true"; shift ;;
      --convert-vhdx)    CONVERT_VHDX="true"; shift ;;
      -h|--help)         usage ;;
      *) die "unknown arg: $1" ;;
    esac
  done
  [[ -z "$TEMPLATE_NAME" || -z "$OUTPUT_DIR" ]] && usage
  CACHE_DIR="${CACHE_DIR:-$OUTPUT_DIR/../cache}"
}

# ---------- workdir + logging ----------
init_workdir() {
  mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  WORK_IMG="$WORK_DIR/sda.qcow2"
}

setup_logging() {
  BUILD_LOG="$OUTPUT_DIR/build.log"
  exec > >(tee -a "$BUILD_LOG") 2>&1
  log_info "log: $BUILD_LOG"
  log_info "template=$TEMPLATE_NAME family=$FAMILY"
}

# ---------- libguestfs backend ----------
ensure_libguestfs_backend() {
  if [[ ! -e /dev/kvm ]]; then
    export LIBGUESTFS_BACKEND=direct
    log_warn "no /dev/kvm — libguestfs running in TCG mode (slower)"
  fi
}

# ---------- cloud image fetch ----------
# Expects family module to have set IMAGE_FILE, IMAGE_URL, SUMS_URL,
# CACHE_FILE_PREFIX before calling. Calls family_parse_checksum_line to
# extract sha256 from the family's SUMS format.
fetch_cloud_image() {
  log_step "[1/7] Fetching upstream checksums"
  curl -fsSL "$SUMS_URL" -o "$WORK_DIR/SUMS"
  EXPECTED_SHA="$( ${FAMILY}_parse_checksum_line < "$WORK_DIR/SUMS" )"
  [[ -z "$EXPECTED_SHA" ]] && die "no checksum for $IMAGE_FILE in SUMS"
  log_info "expected sha256: $EXPECTED_SHA"

  CACHE_FILE="$CACHE_DIR/${CACHE_FILE_PREFIX}-${EXPECTED_SHA:0:12}-amd64.img"
  if [[ ! -f "$CACHE_FILE" ]]; then
    log_step "[2/7] Downloading $IMAGE_URL"
    curl -fL "$IMAGE_URL" -o "$CACHE_FILE.tmp"
    local actual; actual="$(sha256sum "$CACHE_FILE.tmp" | awk '{print $1}')"
    [[ "$actual" != "$EXPECTED_SHA" ]] && { rm -f "$CACHE_FILE.tmp"; die "checksum mismatch: $actual vs $EXPECTED_SHA"; }
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  else
    log_step "[2/7] Cached: $CACHE_FILE"
  fi

  log_step "[3/7] Copy cached image to work file"
  cp --reflink=auto "$CACHE_FILE" "$WORK_IMG"
}

# ---------- eryph-guest-services fetch ----------
fetch_eryph_guest_services() {
  log_step "[3.5/7] Fetching eryph-guest-services"
  EGS_TAR="$WORK_DIR/egs-linux.tar.gz"
  EGS_URL="$(curl -fsSL https://releases.dbosoft.eu/eryph/guest-services/index.json | python3 -c '
import sys, json
d = json.load(sys.stdin)
v = d.get("stableVersion") or d["latestVersion"]
files = d["versions"][v]["files"]
print(next(f["url"] for f in files if f.get("os")=="linux" and f.get("arch")=="amd64" and f["filename"].startswith("egs_")))
')"
  [[ -z "$EGS_URL" ]] && die "no egs URL found"
  log_info "url: $EGS_URL"
  curl -fsSL "$EGS_URL" -o "$EGS_TAR"
  mkdir -p "$WORK_DIR/guest-services"
  tar -xzf "$EGS_TAR" -C "$WORK_DIR/guest-services"
}

# ---------- shared virt-customize arg builders ----------
# All builders APPEND to the global VC_ARGS array. The build.sh assembles
# the full argv by calling family + shared builders in the desired order.

declare -ga VC_ARGS=()

reset_vc_args() { VC_ARGS=(); }

# eryph-guest-services + cloud-init drop-ins. Family-agnostic.
# DATASOURCE_FILE selects the kvm or hyperv variant of 91-eryph.cfg.
common_provision_vc_args() {
  local datasource_file="${1:-91-eryph-kvm.cfg}"
  VC_ARGS+=(
    --mkdir /opt/eryph
    --copy-in "$WORK_DIR/guest-services:/opt/eryph"
    --upload "$FILES_DIR/eryph-guest-services.service:/etc/systemd/system/eryph-guest-services.service"
    --link '/etc/systemd/system/eryph-guest-services.service:/etc/systemd/system/multi-user.target.wants/eryph-guest-services.service'
    --upload "$FILES_DIR/$datasource_file:/etc/cloud/cloud.cfg.d/91-eryph.cfg"
    --upload "$FILES_DIR/92-reporting.cfg:/etc/cloud/cloud.cfg.d/92-reporting.cfg"
  )
}

# Template finalize: machine identity, host keys, transient state, cloud-init.
# Family-agnostic; pkg-manager cache cleanup is done by the family hook after.
common_cleanup_vc_args() {
  VC_ARGS+=(
    --truncate /etc/machine-id
    --delete /var/lib/dbus/machine-id
    --run-command 'rm -f /etc/ssh/ssh_host_*'
    --run-command 'rm -rf /tmp/* /var/tmp/* /root/.bash_history /home/ubuntu/.bash_history 2>/dev/null || true'
    --run-command 'find /var/log -type f -exec truncate --size=0 {} +'
    --run-command 'rm -f /var/lib/systemd/random-seed'
    --run-command 'cloud-init clean --logs --seed'
  )
}

# ---------- output emission ----------
emit_qcow2() {
  log_step "[5/7] Sparsify + emit qcow2 (zstd-compressed) to kvm/amd64/"
  virt-sparsify --in-place "$WORK_IMG"
  mkdir -p "$KVM_DIR"
  qemu-img convert -p -c -O qcow2 -o compression_type=zstd "$WORK_IMG" "$KVM_DIR/sda.qcow2"
}

emit_vhdx() {
  local src="$1"
  log_step "[7/7] Sparsify + convert vhdx to hyperv/amd64/"
  virt-sparsify --in-place "$src"
  mkdir -p "$HV_DIR"
  qemu-img convert -p -O vhdx -o subformat=dynamic "$src" "$HV_DIR/sda.vhdx"
}

emit_metadata_and_catlet() {
  cat > "$STAGE_DIR/metadata.json" <<EOF
{
  "_os_type": "linux",
  "_os_name": "$TEMPLATE_NAME",
  "build_date": "$(date -Iseconds)",
  "source_image": "$IMAGE_URL",
  "source_sha256": "$EXPECTED_SHA",
  "family": "$FAMILY"
}
EOF
  cp "$FILES_DIR/catlet.yaml" "$STAGE_DIR/catlet.yaml"
}
