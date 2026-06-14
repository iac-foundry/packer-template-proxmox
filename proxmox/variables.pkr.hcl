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

variable "vm_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
}

variable "vm_memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "iso_file" {
  type        = string
  description = "ISO path on Proxmox storage, e.g. 'local:iso/ubuntu-24.04.4-live-server-amd64.iso'. Use download-iso.sh to fetch first."
}

variable "ssh_username" {
  type        = string
  description = "SSH username for initial access"
  default     = "ubuntu"
}

variable "ssh_password" {
  type        = string
  sensitive   = true
  description = "SSH password for initial access"
  default     = "ubuntu"
}
