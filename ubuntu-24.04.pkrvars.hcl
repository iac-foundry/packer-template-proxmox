# Ubuntu 24.04 LTS (Noble) — amd64
# Ubuntu-version-specific variables only.
# Proxmox credentials are read from environment variables (PROXMOX_URL, PROXMOX_USER,
# PROXMOX_PASSWORD, PROXMOX_NODE, PROXMOX_STORAGE, PROXMOX_ISO_STORAGE).
#
# iso_filename is the bare filename only. The storage prefix is taken from
# PROXMOX_ISO_STORAGE automatically — no need to repeat it here.
# Use download-iso.sh to cache the ISO on Proxmox before building.
#
# Override any variable at build time with: PKR_VAR_vm_cores=4 packer build ...
#
# Current latest (24.04.4):
#   url:      https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso
#   checksum: e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433
#
# To refresh:
#   curl -s https://releases.ubuntu.com/24.04/SHA256SUMS | grep live-server-amd64

vm_name      = "ubuntu-24.04"
vm_id        = 9001
iso_filename = "ubuntu-24.04.4-live-server-amd64.iso"

vm_cores  = 2
vm_memory = 4096
