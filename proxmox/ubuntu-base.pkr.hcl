source "proxmox-iso" "ubuntu" {
  # Proxmox API settings
  proxmox_url              = local.proxmox_api_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # Boot ISO — must already exist on Proxmox storage (use download-iso.sh to fetch it)
  boot_iso {
    iso_file = local.iso_file
    unmount  = true
  }

  # VM identification
  vm_id   = var.vm_id
  vm_name = var.vm_name

  # VM hardware
  memory  = var.vm_memory
  cores   = var.vm_cores
  sockets = 1

  # EFI firmware — preferred over SeaBIOS for production compatibility.
  # pre_enrolled_keys = false means no Secure Boot keys are enrolled,
  # which keeps the template usable across environments.
  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.proxmox_storage
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  # Storage and disk
  scsi_controller = "virtio-scsi-pci"

  disks {
    type         = "virtio"
    disk_size    = "20G"
    storage_pool = var.proxmox_storage
  }

  # Networking
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init datasource ISO — Packer uploads user-data + meta-data as a cidata ISO
  # directly to Proxmox storage. With UEFI, boot device selection is handled by
  # EFI boot entries, so device ordering is not a concern for boot — ide3 just
  # keeps it out of the way of the primary boot ISO on ide2.
  additional_iso_files {
    # user-data is templated so the build-VM password hash is injected at build
    # time (build-template.sh generates a random one) rather than committed.
    cd_content = {
      "user-data" = templatefile("http/user-data.pkrtpl", {
        password_hash = var.ssh_password_hash
      })
      "meta-data" = file("http/meta-data")
    }
    cd_label         = "cidata"
    device           = "ide3"
    iso_storage_pool = var.proxmox_iso_storage
    unmount          = true
  }

  boot_wait = "5s"
  boot_command = [
    "<wait3s>c<wait3s>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud ip=dhcp<enter><wait3s>",
    "initrd /casper/initrd<enter><wait3s>",
    "boot<enter>"
  ]

  # SSH communicator
  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "60m"

  # Enable QEMU guest agent so the Proxmox plugin can discover the VM's IP
  # address after install. Without this, Packer has no way to find where to SSH.
  qemu_agent = true

  # Cloud-init drive — attached to the template so Terraform can inject
  # per-clone config (static IP, DNS, SSH keys) at deploy time without
  # needing to re-run Packer.
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage

  # Template settings
  template_name        = "${var.vm_name}-template"
  template_description = "Ubuntu base template built with Packer"
}

build {
  name = "ubuntu-base"
  sources = [
    "source.proxmox-iso.ubuntu"
  ]

  # Run the SOE baseline playbook FROM the bootstrap container AGAINST the VM.
  # Packer injects a temporary SSH key into the VM before invoking ansible,
  # so no sshpass is needed. The ubuntu user has NOPASSWD sudo from late-commands.
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/site.yml"
    user          = var.ssh_username
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=ansible.builtin.default",
      "ANSIBLE_CALLBACK_RESULT_FORMAT=yaml",
    ]
    extra_arguments = [
      "--become",
    ]
  }

  # Seal the template: strip identity, cloud-init state, SSH host keys,
  # and netplan config so every clone comes up with a fresh identity.
  # Must run last — after all provisioning is complete.
  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /etc/netplan/50-cloud-init.yaml /etc/netplan/00-installer-config.yaml",
      # CRITICAL: the installer (boot_command) leaves "autoinstall ds=nocloud
      # ip=dhcp" in GRUB_CMDLINE_LINUX_DEFAULT because those args sit after the
      # `---` separator and Ubuntu persists post-`---` args to the target's
      # bootloader. The `ip=dhcp` kernel param is cloud-init's HIGHEST-priority
      # network source, so it silently overrides the static ipconfig0 written
      # to each clone's cloud-init drive — the VM always comes up on DHCP.
      # Reset the cmdline so clones honour their cloud-init network config.
      "sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' /etc/default/grub",
      "sudo update-grub",
      # Lock the build-VM password so the template ships with NO usable
      # credential. Clones regain access via cloud-init: injected SSH keys
      # (primary) and/or an optional cipassword break-glass set by the consumer
      # (terraform-proxmox-vm var.ci_password). Locking only disables password
      # auth — key auth and a later cloud-init-set password both still work.
      "sudo passwd -l ubuntu",
      "sudo sync"
    ]
  }
}
