# Example: deploy two VMs on Proxmox from a cloud-init template using the proxmox-vm module.
terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66, < 1.0"
    }
  }
}

# PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN come from the environment (never commit them).
provider "proxmox" {
  insecure = false
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

locals {
  vms = {
    app01 = { ip = "10.20.3.41/25", cores = 2, memory = 4096 }
    app02 = { ip = "10.20.3.42/25", cores = 2, memory = 4096 }
  }
}

module "vm" {
  source   = "../../modules/proxmox-vm"
  for_each = local.vms

  vm_name           = each.key
  target_node       = "pve01"
  clone_template_id = 9000
  cores             = each.value.cores
  memory_mb         = each.value.memory
  disk_size_gb      = 40
  bridge            = "vmbr0"
  vlan_id           = 30
  ip_cidr           = each.value.ip
  gateway           = "10.20.3.1"
  dns_servers       = ["10.20.3.21", "10.20.3.22"]
  dns_domain        = "corp.example.com"
  ssh_public_keys   = var.ssh_public_keys
  tags              = ["terraform", "app"]
}

output "vm_addresses" {
  value = { for k, m in module.vm : k => m.ipv4_addresses }
}
