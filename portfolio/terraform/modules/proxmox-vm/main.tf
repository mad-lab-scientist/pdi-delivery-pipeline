# Clone a VM from a cloud-init template on Proxmox VE and set its sizing, network and cloud-init config.
# Uses the bpg/proxmox provider. Pair with virtualization/proxmox/pve-cloudinit-template.sh for the template.
terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66, < 1.0"
    }
  }
}

locals {
  use_dhcp = var.ip_cidr == "dhcp"
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.target_node
  vm_id     = var.vmid != 0 ? var.vmid : null
  tags      = var.tags

  clone {
    vm_id = var.clone_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = local.use_dhcp ? "dhcp" : var.ip_cidr
        gateway = local.use_dhcp ? null : var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_account {
      username = var.ci_user
      keys     = var.ssh_public_keys
    }
  }

  lifecycle {
    precondition {
      condition     = local.use_dhcp || var.gateway != null
      error_message = "gateway is required when ip_cidr is a static address."
    }
  }
}
