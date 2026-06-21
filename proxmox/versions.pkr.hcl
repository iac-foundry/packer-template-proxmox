packer {
  required_plugins {
    # Pinned exactly so every machine resolves the same plugin — the container
    # (fresh init each run) and any host stay in lockstep. proxmox >= 1.2.0 is
    # required for the `boot_iso {}` block used in ubuntu-base.pkr.hcl; a stale
    # 1.1.x cache satisfies a loose ">= 1.1.0" and silently breaks the build.
    proxmox = {
      version = "1.2.3"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = "1.1.5"
      source  = "github.com/hashicorp/ansible"
    }
  }
}
