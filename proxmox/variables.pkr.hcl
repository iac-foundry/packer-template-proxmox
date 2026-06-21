variable "proxmox_url" {
  type        = string
  description = "Proxmox base URL, e.g. https://pve.example.com:8006 (reads from PROXMOX_URL env var)"
  default     = env("PROXMOX_URL")
}

locals {
  proxmox_api_url = "${trimsuffix(var.proxmox_url, "/")}/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox username (reads from PROXMOX_USER env var)"
  default     = env("PROXMOX_USER")
}

variable "proxmox_password" {
  type        = string
  sensitive   = true
  description = "Proxmox password (reads from PROXMOX_PASSWORD env var)"
  default     = env("PROXMOX_PASSWORD")
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name (reads from PROXMOX_NODE env var, defaults to 'pve')"
  default     = env("PROXMOX_NODE") != "" ? env("PROXMOX_NODE") : "pve"
}

variable "proxmox_storage" {
  type        = string
  description = "Proxmox storage pool for VM disks (reads from PROXMOX_STORAGE env var, defaults to 'local-lvm')"
  default     = env("PROXMOX_STORAGE") != "" ? env("PROXMOX_STORAGE") : "local-lvm"
}

variable "proxmox_iso_storage" {
  type        = string
  description = "Proxmox storage pool for ISOs (reads from PROXMOX_ISO_STORAGE env var, defaults to 'local')"
  default     = env("PROXMOX_ISO_STORAGE") != "" ? env("PROXMOX_ISO_STORAGE") : "local"
}

variable "vm_name" {
  type        = string
  description = "Name of the VM template being built (e.g., ubuntu-22.04)"
}

variable "vm_id" {
  type        = number
  description = "Proxmox VM ID for the build VM. Must be unique per active template — use distinct IDs per Ubuntu version. 9000 is taken by ubuntu-22.04-template; 24.04 owns 9001."
  default     = 9001
}

variable "vm_cores" {
  type        = number
  description = "Number of CPU cores. Override with PKR_VAR_vm_cores."
  default     = 2
}

variable "vm_memory" {
  type        = number
  description = "Memory in MB. Override with PKR_VAR_vm_memory."
  default     = 4096
}

variable "iso_filename" {
  type        = string
  description = "ISO filename only (e.g. ubuntu-24.04.4-live-server-amd64.iso). Storage pool is taken from PROXMOX_ISO_STORAGE."
}

locals {
  iso_file = "${var.proxmox_iso_storage}:iso/${var.iso_filename}"
}

variable "ssh_username" {
  type        = string
  description = "SSH username Packer uses to reach the build VM."
  default     = "ubuntu"
}

# Build-VM password (and its matching crypt hash) are used ONLY during the
# Packer build so the communicator can SSH in. build-template.sh generates a
# random per-build value and passes both via PKR_VAR_*. The template is sealed
# with this account LOCKED, so the password never ships on a clone. The
# "ubuntu" fallback below keeps a manual `packer build` working without the
# script; ssh_password and ssh_password_hash MUST stay in sync (hash of plaintext).
variable "ssh_password" {
  type        = string
  sensitive   = true
  description = "Build-VM password Packer uses to SSH in (locked at seal; never ships)."
  default     = "ubuntu"
}

variable "ssh_password_hash" {
  type        = string
  sensitive   = true
  description = "SHA-512 crypt hash of ssh_password, injected into the autoinstall user-data. Must match ssh_password."
  # Hash of "ubuntu" — fallback for manual builds; build-template.sh overrides.
  default = "$6$BhUKZKCNSlzyKhvO$5vlOl2e6Zoc1YOiwryugkReHduDaPCQndY7Z4qwAT2.mLnLBFkN19sT5v0vHNgRJPpVQSU2HriZRlbQpyUY7j/"
}
