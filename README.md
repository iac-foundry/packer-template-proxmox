# packer-template-proxmox

Packer templates for building Ubuntu VM templates on Proxmox.

## Overview

This repository contains reusable Packer configurations to build thin Ubuntu 22.04 LTS and 24.04 LTS VM templates for Proxmox.

- **ubuntu-base**: Minimal, thin-provisioned Ubuntu template with essential packages (qemu-guest-agent, SSH, Python)

Downstream customization (Docker, networking, services, etc.) is handled via Terraform and Ansible, not baked into the template. This keeps templates reusable and lightweight.

## Prerequisites

- **Packer** >= 1.8.0
- **Proxmox** running and accessible via API
- **Proxmox API credentials** (username, password, API token, or API key)
- **Ubuntu ISOs** downloaded or accessible via HTTP
- Internet access for downloading packages during build

## Quick Start

**Proxmox credentials are read from environment variables** (typically from your bootstrap
container's `.env`): `PROXMOX_URL`, `PROXMOX_USER`, `PROXMOX_PASSWORD`, and optionally
`PROXMOX_NODE`, `PROXMOX_STORAGE`, `PROXMOX_ISO_STORAGE`.

### Recommended: one command

`build-template.sh` caches the ISO, generates a throwaway build password, and builds. It
takes `all` (default), `2404`, or `2204`, and works both inside the bootstrap container and
on a host with the tools installed:

```bash
# Inside the bootstrap container (pinned toolchain — preferred)
cd ~/workspace/vernify/bootstrap-container && source .env
docker compose run --rm bootstrap \
  bash /workspace/iac-foundry/packer-template-proxmox/build-template.sh 2404

# Or on the host (packer, openssl, jq, curl installed)
source ~/workspace/vernify/bootstrap-container/.env
./build-template.sh all
```

The script prints a per-build break-glass password for the `ubuntu` user — valid only on a
*failed* build VM (the finished template ships with that account locked; see
[Security](#security-considerations)).

### Manual / advanced

The per-version `.pkrvars.hcl` carry only `vm_name`, `vm_id`, `iso_filename`, and sizing —
**no credentials**. To drive Packer directly:

```bash
packer init proxmox/
packer validate -var-file=ubuntu-24.04.pkrvars.hcl proxmox/
packer build -force -var-file=ubuntu-24.04.pkrvars.hcl proxmox/
```

> Always invoke Packer against the `proxmox/` **directory**, never a single `.pkr.hcl` file —
> a single file silently skips `variables.pkr.hcl`/`versions.pkr.hcl`.

### Verify in Proxmox

After the build completes, log into your Proxmox web UI:

```
https://your-proxmox-host:8006
```

Navigate to **Datacenter** → **Nodes** → **[your-node]** → **Qemu** and verify the new templates appear:
- `ubuntu-22.04-template`
- `ubuntu-24.04-template`

## Template Customization

### Modify base packages

Edit `ansible/site.yml` to add or remove packages:

```yaml
- name: Install base packages
  apt:
    name:
      - your-new-package
    state: present
  become: true
```

### Modify container-host packages

Edit `ansible/container-host.yml` to customize Docker/Podman configuration.

### Adjust disk size

Modify the `disk_size` in the `.pkr.hcl` files:

```hcl
disks {
  disk_size = "30G"  # Change this value
}
```

### Use a different Ubuntu ISO

ISOs are pulled to Proxmox storage by `download-iso.sh` and referenced by bare filename.
Set `iso_filename` in the relevant `.pkrvars.hcl` (the storage prefix comes from
`PROXMOX_ISO_STORAGE`), and add the matching filename/URL/checksum to `build-template.sh`'s
`ISO_FILE`/`ISO_URL`/`ISO_SUM` maps so it gets cached automatically.

## Architecture

### File Structure

```
packer-template-proxmox/
├── README.md                          # This file
├── build-template.sh                  # Primary entrypoint: build [all|2404|2204]
├── download-iso.sh                    # Pull an ISO to Proxmox storage via API
├── verify-templates.sh                # packer validate wrapper
├── ubuntu-22.04.pkrvars.hcl           # Org-neutral variables for 22.04 (committed example)
├── ubuntu-24.04.pkrvars.hcl           # Org-neutral variables for 24.04 (committed example)
├── proxmox/
│   ├── variables.pkr.hcl              # Variable definitions
│   ├── versions.pkr.hcl               # Required plugins (hashicorp/proxmox, ansible)
│   ├── ubuntu-base.pkr.hcl            # Base template (build + seal)
│   └── http/
│       ├── user-data.pkrtpl           # Autoinstall template (password hash injected)
│       └── meta-data                  # Autoinstall meta-data
└── ansible/
    └── site.yml                       # SOE baseline playbook (runs from container)
```

### Build Flow

1. **Packer** provisions a VM on Proxmox from the Ubuntu ISO; autoinstall sets up the
   `ubuntu` user with the (random, per-build) password whose hash is injected into
   `user-data.pkrtpl`.
2. **Cloud-init** performs initial boot configuration; Packer SSHes in with that password.
3. **Ansible** (`site.yml`) installs the SOE baseline + qemu-guest-agent.
4. **Seal** removes cloud-init state/SSH host keys, resets the GRUB cmdline (so clones
   honour their static IP), and **locks the `ubuntu` account** (template ships
   credential-less).
5. **Proxmox** converts the VM into a reusable template.

## Troubleshooting

### Build hangs at "Waiting for SSH"

- Ensure cloud-init is completing successfully. Check Proxmox console for boot messages.
- Verify the HTTP server is accessible from the VM (check `http_port_min`/`http_port_max`).
- Increase `ssh_timeout` in your `.pkrvars.hcl` file.

### ISO checksum mismatch

- Download the correct ISO checksum from Ubuntu's releases page.
- Update the `iso_checksum` variable in your `.pkrvars.hcl` file.

### Proxmox API connection fails

- Verify `proxmox_url`, `proxmox_username`, and `proxmox_password` are correct.
- Check that your Proxmox user has API permissions.
- Verify the Proxmox node name (`proxmox_node`) exists.

### Template not appearing in Proxmox

- Check Packer build output for errors.
- Verify the VM was created but failed to convert to template.
- Check Proxmox logs: `tail -f /var/log/syslog` on the Proxmox host.

## Security Considerations

- **Templates ship credential-less.** The `ubuntu` account is locked at seal (`passwd -l`),
  so no usable password is baked into the image. Per-host access on clones comes from
  cloud-init: injected SSH keys (primary) and an optional `ci_password` break-glass set by
  the consumer (`terraform-proxmox-vm`).
- **The build password is random and per-build.** `build-template.sh` generates it, prints
  it, and injects its hash into `user-data.pkrtpl` — it exists only so Packer can SSH into
  the build VM, and is your break-glass into a *failed* build. It never ships.
- **Never commit** real `.pkrvars.hcl` (gitignored) or a password hash in `user-data.pkrtpl`
  (use the `${password_hash}` placeholder). Credentials come from the bootstrap `.env`.
- Prefer SSH keys for all clone access; treat `ci_password` as debug-only.

## Contributing

When modifying these templates:

1. Test against both Ubuntu 22.04 and 24.04
2. Update the README if you change the structure
3. Keep the templates org-neutral (no Vernify-specific assumptions)
4. Document any new Ansible roles or playbooks

## References

- [Proxmox Packer Provider](https://github.com/hashicorp/packer-plugin-proxmox)
- [Packer Documentation](https://www.packer.io/docs)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Cloud-init Documentation](https://cloud-init.io/)
- [Ansible Documentation](https://docs.ansible.com/)
