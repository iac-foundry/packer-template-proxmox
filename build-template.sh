#!/usr/bin/env bash
# build-template.sh — download ISO(s) and build Ubuntu template(s) in Proxmox.
#
# Works both inside the bootstrap container and on a host with the tools
# (packer, openssl, jq, curl) installed — it locates the repo from its own path,
# so there is nothing to hardcode.
#
# In the container (recommended — pinned toolchain):
#   cd ~/path/to/bootstrap-container && source .env
#   docker compose run --rm bootstrap \
#     bash /workspace/iac-foundry/packer-template-proxmox/build-template.sh [all|2404|2204]
#
# On the host:
#   source ~/path/to/bootstrap-container/.env
#   ./build-template.sh [all|2404|2204]
#
# Target selector (first arg, default "all"):
#   all   — build both 22.04 and 24.04
#   2404  — build 24.04 only
#   2204  — build 22.04 only
#
# Environment variables (sourced from .env via docker compose):
#   Required: PROXMOX_URL, PROXMOX_USER, PROXMOX_PASSWORD
#   Optional: PROXMOX_NODE, PROXMOX_STORAGE (default local-lvm), PROXMOX_ISO_STORAGE (default local)
#
# Any pkrvars variable can be overridden at runtime via PKR_VAR_<name>, e.g.:
#   PKR_VAR_vm_cores=4 ... build-template.sh 2404

set -euo pipefail

# Resolve the repo root from the script's own location so this works both inside
# the bootstrap container and on a host with the tools installed — no hardcoded
# /workspace path.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO}"

# ── target selection ─────────────────────────────────────────────────────────
TARGET="${1:-all}"
case "${TARGET}" in
  all)  versions=(2204 2404) ;;
  2204) versions=(2204) ;;
  2404) versions=(2404) ;;
  *) echo "usage: $(basename "$0") [all|2404|2204]   (default: all)" >&2; exit 1 ;;
esac

for var in PROXMOX_URL PROXMOX_USER PROXMOX_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: ${var} is not set. Source .env before running." >&2
    exit 1
  fi
done

# ── per-build throwaway credential ───────────────────────────────────────────
# Used ONLY so Packer can SSH into the build VM. The template is sealed with the
# ubuntu account LOCKED (see proxmox/ubuntu-base.pkr.hcl), so this never ships on
# a clone — its sole purpose is letting an operator console into a FAILED build
# (packer keeps the VM on error). Per-host access on clones comes from cloud-init
# SSH keys + the consumer's optional ci_password, not from this.
# openssl rand (no pipe) avoids the head/SIGPIPE + pipefail trap.
BUILD_PASSWORD="$(openssl rand -hex 24)"
export PKR_VAR_ssh_password="${BUILD_PASSWORD}"
export PKR_VAR_ssh_password_hash="$(openssl passwd -6 "${BUILD_PASSWORD}")"

cat <<EOF

────────────────────────────────────────────────────────────────────
  Build-VM break-glass password (this run only):
      user: ubuntu
      pass: ${BUILD_PASSWORD}
  Valid only on a FAILED build VM. Templates ship with ubuntu LOCKED.
────────────────────────────────────────────────────────────────────

EOF

# ── per-version ISO + pkrvars metadata ───────────────────────────────────────
declare -A ISO_FILE=(
  [2204]="ubuntu-22.04.5-live-server-amd64.iso"
  [2404]="ubuntu-24.04.4-live-server-amd64.iso"
)
declare -A ISO_URL=(
  [2204]="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
  [2404]="https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
)
declare -A ISO_SUM=(
  [2204]="9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
  [2404]="e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
)
declare -A PKRVARS=(
  [2204]="ubuntu-22.04.pkrvars.hcl"
  [2404]="ubuntu-24.04.pkrvars.hcl"
)

# ── init plugins (no-op if already cached) ───────────────────────────────────
packer init proxmox/

# ── build selected template(s) (force-replaces existing) ─────────────────────
for v in "${versions[@]}"; do
  echo "==> Caching ISO for ${v}: ${ISO_FILE[$v]}"
  bash download-iso.sh "${ISO_FILE[$v]}" "${ISO_URL[$v]}" "${ISO_SUM[$v]}"
  echo "==> Building template ${v}"
  packer build -force -var-file="${PKRVARS[$v]}" proxmox/
done
