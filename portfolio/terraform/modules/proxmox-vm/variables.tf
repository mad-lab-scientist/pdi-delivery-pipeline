variable "vm_name" {
  type        = string
  description = "VM name / hostname."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.vm_name))
    error_message = "vm_name must be a valid lowercase hostname."
  }
}

variable "target_node" {
  type        = string
  description = "Proxmox node to create the VM on."
}

variable "clone_template_id" {
  type        = number
  description = "VMID of the cloud-init template to clone."
}

variable "vmid" {
  type        = number
  default     = 0
  description = "Desired VMID (0 lets Proxmox pick the next free one)."
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 4096
}

variable "disk_size_gb" {
  type    = number
  default = 32
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  type        = number
  default     = null
  description = "VLAN tag, or null for untagged."
}

variable "ip_cidr" {
  type        = string
  description = "Static IPv4 with prefix, e.g. 10.20.3.40/25, or \"dhcp\"."
}

variable "gateway" {
  type        = string
  default     = null
  description = "Default gateway (required for static IP)."
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

variable "dns_domain" {
  type    = string
  default = null
}

variable "ci_user" {
  type    = string
  default = "opsadmin"
}

variable "ssh_public_keys" {
  type        = list(string)
  default     = []
  description = "SSH public keys authorized for the cloud-init user."
}

variable "tags" {
  type    = list(string)
  default = []
}
