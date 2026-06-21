# Phase 1 — Packer Base Template Runbook

This runbook guides you through Phase 1 of the Vernify greenfield bootstrap using the bootstrap container to build Ubuntu 22.04 and 24.04 templates in Proxmox.

## Overview

**What:** Build reusable Ubuntu 22.04 and 24.04 VM templates in Proxmox.  
**How:** Run Packer from the bootstrap container, which supplies Proxmox credentials from `.env`.  
**Output:** Two reusable templates (ubuntu-22.04 and ubuntu-24.04) available for cloning in Phases 2+.

**Design:** Templates are thin-provisioned with only essential packages. Downstream customization (Docker, services, networking) happens via Terraform and Ansible per-VM.

## Prerequisites

✅ Bootstrap container is built and ready (`docker compose build` completed)  
✅ `.env` is filled in with Proxmox credentials:
  - `PROXMOX_URL`
  - `PROXMOX_USER`
  - `PROXMOX_PASSWORD`
  - `PROXMOX_NODE` (optional, defaults to `pve`)
  - `PROXMOX_STORAGE` (optional, defaults to `local`)

✅ Ubuntu ISOs can be downloaded from the internet (or cached locally)

## Step 1: Start the Bootstrap Container

From the `bootstrap-container` directory:

```bash
cd ~/workspace/vernify/bootstrap-container

# Source .env (optional, docker compose loads it automatically)
source .env

# Start the container
docker compose run -it --rm bootstrap
```

You're now inside the container with all secrets loaded and `/workspace` mounted.

## Step 2: Verify Proxmox Connectivity

Inside the container, test your Proxmox connection:

```bash
# Verify Proxmox environment variables are set
echo "URL: $PROXMOX_URL"
echo "User: $PROXMOX_USER"

# Test API connectivity (requires curl)
curl -k -X GET \
  "$PROXMOX_URL/api2/json/version" \
  -H "Authorization: PVEAPIToken=$PROXMOX_USER:$PROXMOX_TOKEN" \
  --max-time 5

# Or with password auth (less preferred):
curl -k -X POST \
  "$PROXMOX_URL/api2/json/access/ticket" \
  -d "username=$PROXMOX_USER&password=$PROXMOX_PASSWORD"
```

If successful, you'll see Proxmox version info. If it fails, check your credentials in `.env`.

## Step 3: Verify Templates (Optional)

You can validate the templates first without building (useful for catching issues early):

```bash
cd /workspace/iac-foundry/packer-template-proxmox

# Run the verification script
bash verify-templates.sh
```

This script will:
1. Check Packer is installed
2. Initialize the Proxmox plugin
3. Validate the ubuntu-base template

If all checks pass, you'll see ✅. If any fail, the script shows which step failed and why.

## Step 4: Build the Template(s)

`build-template.sh` does everything: caches the ISO, generates a throwaway build password,
inits plugins, and builds. It takes `all` (default), `2404`, or `2204`. Proxmox credentials
are read from the `.env` you already sourced — there is nothing to copy or edit.

From the host (the container is launched for you):

```bash
cd ~/workspace/vernify/bootstrap-container && source .env

# Build both, or pass 2404 / 2204 for one
docker compose run --rm bootstrap \
  bash /workspace/iac-foundry/packer-template-proxmox/build-template.sh all
```

The script prints a **per-build break-glass password** for the `ubuntu` user near the top:

```
  Build-VM break-glass password (this run only):
      user: ubuntu
      pass: <random>
```

That password is only valid on a *failed* build VM (Packer keeps it on error) — note it down
until the build succeeds, then discard it. The finished template ships with the `ubuntu`
account **locked**; clones get their access from cloud-init (SSH keys + the consumer's
optional `ci_password`), never from this.

**Expected duration:** ~12–16 min per version on first run (ISO download dominates); ~3–4 min
when the ISO is already cached.

Optional — validate first without building, or drive Packer manually:

```bash
docker compose run --rm bootstrap bash -c \
  'cd /workspace/iac-foundry/packer-template-proxmox && bash verify-templates.sh'
```

## Step 5: Verify Templates in Proxmox

Exit the bootstrap container:

```bash
exit
```

In your web browser, log into the Proxmox web UI:

```
https://your-proxmox-host:8006
```

Navigate to:  
**Datacenter** → **Nodes** → **[your-node]** → **Qemu**

You should see **two new templates**:
- `ubuntu-22.04-template`
- `ubuntu-24.04-template`

Click each to verify:
- ✅ Correct size (~20 GB)
- ✅ 2 CPU cores, 2048 MB RAM (or your configured values)
- ✅ Correctly shows as a template (icon/badge)

These thin templates are ready to be cloned and customized downstream via Terraform and Ansible.

## Troubleshooting

### "Waiting for SSH" times out after 20m

**Cause:** Cloud-init is not completing successfully, or the VM doesn't have network access.

**Solution:**
1. Check the Proxmox console for the temporary VM — it should show boot messages
2. Verify the HTTP server is running on the Packer host (should be on port 8802+)
3. Increase `ssh_timeout` in your `.pkrvars.hcl` file to 30m:
   ```hcl
   ssh_timeout = "30m"
   ```
4. Re-run the build

### "ISO checksum mismatch"

**Cause:** The downloaded ISO doesn't match the checksum (corrupted download or wrong ISO).

**Solution:**
1. Verify the checksum from https://releases.ubuntu.com/22.04/SHA256SUMS
2. Update the `iso_checksum` in your `.pkrvars.hcl`
3. Clear Packer cache: `rm -rf ~/.cache/packer`
4. Re-run the build

### "proxmox_url not found in env" error

**Cause:** Environment variables from `.env` aren't loaded in the container.

**Solution:**
1. Inside the container, manually source `.env`:
   ```bash
   source ~/.env  # or wherever .env is mounted
   ```
2. Or create the `.pkrvars.hcl` file directly with hardcoded values (but don't commit it)

### Template appears in Proxmox but has size 0 GB

**Cause:** Disk allocation failed during provisioning.

**Solution:**
1. Delete the empty template
2. Check Proxmox storage pool has enough free space
3. Check `/var/log/syslog` on the Proxmox host for disk errors
4. Retry the build with a smaller disk (`disk_size = "15G"`)

## Next Steps

✅ **Phase 1 complete** — you now have Ubuntu 22.04 and 24.04 templates ready.

**Proceed to Phase 2:**
- Create TFC workspaces
- Build a Proxmox VM module in Terraform
- Provision `sec01` by cloning the base template

See [../HOMELAB_GREENFIELD_BOOTSTRAP.md](../roadmap/HOMELAB_GREENFIELD_BOOTSTRAP.md) for Phase 2 instructions.

## References

- [Proxmox Packer Plugin](https://github.com/hashicorp/packer-plugin-proxmox)
- [Packer Docs](https://www.packer.io/docs)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Cloud-init Docs](https://cloud-init.io/)
