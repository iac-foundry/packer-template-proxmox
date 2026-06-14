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

### 1. Prepare variables

**Proxmox credentials are read from environment variables** (typically from your bootstrap container's `.env`):
- `PROXMOX_URL`
- `PROXMOX_USER`
- `PROXMOX_PASSWORD`
- `PROXMOX_NODE` (optional, defaults to `pve`)
- `PROXMOX_STORAGE` (optional, defaults to `local`)

Just copy the Ubuntu-version-specific variable files:

```bash
cp ubuntu-22.04.pkrvars.hcl.example ubuntu-22.04.pkrvars.hcl
cp ubuntu-24.04.pkrvars.hcl.example ubuntu-24.04.pkrvars.hcl
```

No need to edit — the examples already have correct ISO URLs and checksums. Customize if you want different sizing (vm_cores, vm_memory).

### 2. Initialize Packer

```bash
packer init proxmox/
```

This downloads the Proxmox Packer plugin.

### 3. Validate the template

```bash
packer validate -var-file=ubuntu-22.04.pkrvars.hcl proxmox/
packer validate -var-file=ubuntu-22.04.pkrvars.hcl proxmox/ubuntu-container-host.pkr.hcl
```

### 4. Build the template

#### Build Ubuntu 22.04:

```bash
packer build -var-file=ubuntu-22.04.pkrvars.hcl proxmox/
```

#### Build Ubuntu 24.04:

```bash
packer build -var-file=ubuntu-24.04.pkrvars.hcl proxmox/
```

### 5. Verify in Proxmox

After the build completes, log into your Proxmox web UI:

```
https://your-proxmox-host:8006
```

Navigate to **Datacenter** → **Nodes** → **[your-node]** → **Qemu** and verify the new templates appear:
- `ubuntu-22.04-template`
- `ubuntu-24.04-template`

## Using with the Bootstrap Container

The bootstrap container can execute these builds with your Proxmox credentials sourced from `.env`:

```bash
# Inside the bootstrap container
cd /workspace/iac-foundry/packer-template-proxmox

# Create variable files from bootstrap secrets
cat > ubuntu-22.04.pkrvars.hcl << EOF
proxmox_url      = "$PROXMOX_URL"
proxmox_username = "$PROXMOX_USER"
proxmox_password = "$PROXMOX_PASSWORD"
proxmox_node     = "pve"
proxmox_storage  = "local"

vm_name    = "ubuntu-22.04"
iso_url    = "https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso"
iso_checksum = "e240e4b801f61bda86e1eb88ec917110e9ad972cc5b146d47d55d595bb393466"

vm_cores   = 2
vm_memory  = 2048

ssh_username = "ubuntu"
ssh_password = "ubuntu"
EOF

# Build the template
packer init proxmox/
packer build -var-file=ubuntu-22.04.pkrvars.hcl proxmox/
```

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

Override the `iso_url` and `iso_checksum` in your `.pkrvars.hcl` file or via CLI:

```bash
packer build \
  -var-file=ubuntu-22.04.pkrvars.hcl \
  -var iso_url="https://custom-mirror.local/ubuntu-22.04.iso" \
  -var iso_checksum="sha256:..." \
  proxmox/
```

## Architecture

### File Structure

```
packer-template-proxmox/
├── README.md                          # This file
├── ubuntu-22.04.pkrvars.hcl.example   # Example variables for 22.04
├── ubuntu-24.04.pkrvars.hcl.example   # Example variables for 24.04
├── proxmox/
│   ├── variables.pkr.hcl              # Variable definitions
│   ├── ubuntu-base.pkr.hcl            # Base template
│   ├── ubuntu-container-host.pkr.hcl  # Container-host template
│   └── http/
│       └── user-data                  # Cloud-init configuration
└── ansible/
    ├── requirements.yml               # Ansible collection dependencies
    ├── site.yml                       # Base provisioning playbook
    └── container-host.yml             # Container-host provisioning playbook
```

### Build Flow

1. **Packer** provisions a VM on Proxmox using the Ubuntu ISO
2. **Cloud-init** performs initial boot configuration (networking, SSH)
3. **Ansible** installs and configures packages on the running VM
4. **Cleanup** phase removes cloud-init data and prepares the template
5. **Proxmox** converts the VM into a reusable template

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

- **Do not commit** `.pkrvars.hcl` files containing secrets to version control.
- Use the `.env` mechanism in the bootstrap container to supply credentials.
- The default SSH password in the templates is intentionally weak; it's only used during build.
- For production use, consider using SSH keys instead of passwords.

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
