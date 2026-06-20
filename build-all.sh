#!/usr/bin/env bash
# build-all.sh — download ISOs and build all Ubuntu templates in Proxmox.
#
# Runs inside the bootstrap container. Invoke from your workstation with:
#
#   cd ~/path/to/bootstrap-container
#   source .env
#   docker compose run --rm bootstrap \
#     bash /workspace/iac-foundry/packer-template-proxmox/build-all.sh
#
# Environment variables (all sourced from .env via docker compose):
#   Required: PROXMOX_URL, PROXMOX_USER, PROXMOX_PASSWORD
#   Optional: PROXMOX_NODE (auto-detected), PROXMOX_STORAGE (default: local-lvm),
#             PROXMOX_ISO_STORAGE (default: local)
#
# Any pkrvars variable can be overridden at runtime via PKR_VAR_<name>, e.g.:
#   PKR_VAR_vm_cores=4 docker compose run --rm bootstrap bash build-all.sh

set -euo pipefail

REPO="/workspace/iac-foundry/packer-template-proxmox"

cd "${REPO}"

for var in PROXMOX_URL PROXMOX_USER PROXMOX_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: ${var} is not set. Source .env before running." >&2
    exit 1
  fi
done

# ── cache ISOs on Proxmox (skipped if already present) ───────────────────────
bash download-iso.sh \
  ubuntu-22.04.5-live-server-amd64.iso \
  https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso \
  9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0

bash download-iso.sh \
  ubuntu-24.04.4-live-server-amd64.iso \
  https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso \
  e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433

# ── init plugins (no-op if already cached) ───────────────────────────────────
packer init proxmox/

# ── build templates (force-replaces existing) ─────────────────────────────────
packer build -force -var-file=ubuntu-22.04.pkrvars.hcl proxmox/
packer build -force -var-file=ubuntu-24.04.pkrvars.hcl proxmox/
