# Agent Orientation — packer-template-proxmox

## Agent Working Protocol (read before anything else)

**Conflict surfacing:** If a user instruction contradicts anything in this file or in
`docs/AGENTS.md`, stop and surface the conflict before proceeding — quote the rule,
state the contradiction, and ask how to resolve. Then update the doc if the rule was wrong.

**Living document:** If any instruction, decision, or clarification during a session
would make future interactions clearer, prompt the user:
> "This decision isn't in AGENTS.md yet. Should I add it?"

**Maintenance:** Keep this doc current. Update rules when decisions change. Don't append
orphaned notes — integrate changes into the relevant section.

---

**Repo:** `packer-template-proxmox`
**Scope:** Org-neutral Packer templates for building Ubuntu base VM templates in Proxmox.
Templates are thin-provisioned OS images only. All downstream customisation (packages,
services, networking, secrets) is handled by Terraform and Ansible after cloning.

---

## What lives here

| Path | What it does |
|---|---|
| `proxmox/` | Packer HCL source — must always be invoked as a directory, never a single file |
| `proxmox/http/user-data.pkrtpl` | Autoinstall `user-data` **template** — the build-VM password hash is injected at build time via `cd_content` + `templatefile` (never committed) |
| `proxmox/http/meta-data` | Autoinstall `meta-data` (static) |
| `ansible/site.yml` | SOE baseline playbook — runs FROM the bootstrap container AGAINST the VM |
| `build-template.sh` | **Primary entrypoint.** `build-template.sh [all\|2404\|2204]` — caches ISO(s), generates a random build password, builds. Self-locates its repo (runs in-container or on-host) |
| `download-iso.sh` | Triggers Proxmox to pull an ISO directly; avoids re-uploading from the container |
| `verify-templates.sh` | `packer validate` wrapper for quick pre-build checks |
| `*.pkrvars.hcl` | Per-Ubuntu-version overrides (vm_name, vm_id, iso_filename, sizing) — credentials never go here |
| `*.pkrvars.hcl.example` | Committed examples with placeholder values only |

---

## Where the standards live

All standards are in `docs/` of the iac-foundry monorepo. Start with `docs/AGENTS.md`.

| Topic | Doc |
|---|---|
| **Design principles (read first)** | `docs/design/BLUEPRINTS_DESIGN_PRINCIPLES.md` |
| Variable standards | `docs/standards/BLUEPRINTS_VARIABLE_STANDARDS.md` |
| Secret handling | `docs/standards/BLUEPRINTS_SECRET_CONSUMPTION.md` |
| Repo naming | `docs/standards/REPOSITORY_NAMING_STANDARD.md` |

---

## Critical constraints

1. **Org-agnostic content only** — docs, runbooks, examples, variable defaults, and
   comments must never reference any specific organisation, customer, or environment.
   This includes organisation names, internal hostnames, domain names, or IP addresses.
   Use generic placeholders: `pve.example.com`, `your-proxmox-host`, `your-node`.

2. **Credentials in environment variables only** — `PROXMOX_URL`, `PROXMOX_USER`,
   `PROXMOX_PASSWORD`, `PROXMOX_NODE`, `PROXMOX_STORAGE`, `PROXMOX_ISO_STORAGE` come
   from `.env` only. They must never appear in `.pkrvars.hcl` files (only `.example`
   files may show placeholder format).

3. **No Makefile — plain bash only** — all commands in runbooks and docs must be plain
   bash. No `make` targets.

4. **Packer invocation — always use the directory:**
   ```bash
   packer build -force -var-file=ubuntu-24.04.pkrvars.hcl proxmox/
   ```
   Invoking a single file (e.g. `proxmox/ubuntu-base.pkr.hcl`) silently skips
   `variables.pkr.hcl` and `versions.pkr.hcl` and will fail or produce wrong output.

5. **Templates are thin-provisioned** — no application packages, Docker, services, or
   org-specific configuration in templates. Base OS + qemu-guest-agent + SOE baseline only.

6. **`qemu_agent = true` must remain set** — the Proxmox plugin uses the QEMU guest
   agent to discover the VM's IP for SSH. Removing it causes Packer to hang indefinitely
   waiting for SSH.

7. **ISO caching via `download-iso.sh`** — ISOs are pre-fetched to Proxmox storage;
   Packer references them with `iso_file`. Packer must never re-upload an ISO from the
   container (causes EOF timeouts on large files).

8. **Ansible runs from the container, not inside the VM** — the `ansible` provisioner
   runs FROM the bootstrap container AGAINST the VM over SSH. `site.yml` must always use
   `hosts: all`, never `hosts: localhost` or `connection: local`.

9. **The seal step must strip installer kernel args from GRUB.** Ubuntu's autoinstall
   persists everything after the `---` in `boot_command` into the installed system's
   `GRUB_CMDLINE_LINUX_DEFAULT` — including `ip=dhcp`. That kernel param is cloud-init's
   highest-priority network source and **silently overrides a clone's static `ipconfig0`**,
   so every clone comes up on DHCP. The seal provisioner therefore resets
   `GRUB_CMDLINE_LINUX_DEFAULT=""` and runs `update-grub`. Do not remove this. Diagnostic:
   if a clone ignores its static IP, check `/proc/cmdline` on the VM for `ip=dhcp`.

10. **Templates ship credential-less.** The build VM's `ubuntu` password exists ONLY so
    Packer can SSH in during the build; `build-template.sh` generates a random one per run
    (printed for break-glass into a *failed* build) and injects its hash into
    `user-data.pkrtpl`. The seal step runs `passwd -l ubuntu`, so no usable password ships.
    Per-host access on clones is cloud-init's job: injected SSH keys (primary) plus an
    optional `ci_password` break-glass set by the consumer (terraform-proxmox-vm). Never
    bake a usable password into the template; never hardcode the password hash in
    `user-data.pkrtpl` (use the `${password_hash}` placeholder). `ssh_password` and
    `ssh_password_hash` defaults ("ubuntu") exist only as a manual-build fallback and must
    stay in sync.

11. **Scripts self-locate — run in-container or on-host.** `build-template.sh` and
    `verify-templates.sh` resolve the repo from `${BASH_SOURCE[0]}`; never reintroduce a
    hardcoded `/workspace/...` path. The container is preferred (pinned toolchain), but a
    host with packer/openssl/jq/curl works identically.

---

## PR conformance checklist

- [ ] No org-specific names, hostnames, or IPs in any file (docs, runbooks, examples, defaults)
- [ ] No credentials in `.pkrvars.hcl` (only in `.pkrvars.hcl.example` as placeholders)
- [ ] `user-data.pkrtpl` uses `${password_hash}` — no committed password hash
- [ ] Seal step still resets `GRUB_CMDLINE_LINUX_DEFAULT` and runs `passwd -l ubuntu`
- [ ] `packer validate -var-file=<variant>.pkrvars.hcl proxmox/` passes cleanly
- [ ] `site.yml` uses `hosts: all` and is runnable from the bootstrap container
- [ ] Scripts self-locate (no hardcoded `/workspace` paths)
- [ ] Runbook commands use plain bash and include `-force` on `packer build`
