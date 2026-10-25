variable "name" {
  type        = string
  description = "Name prefix (e.g. hub-prod)."
}

variable "location" {
  type        = string
  default     = "centralus"
  description = "Azure region."
}

variable "address_space" {
  type        = list(string)
  description = "VNet address space, e.g. [\"10.50.0.0/16\"]."
}

variable "subnets" {
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation        = optional(string)
  }))
  description = "Subnets by name. Key 'AzureBastionSubnet' / 'GatewaySubnet' are treated as Azure reserved."
}

variable "allowed_ssh_rdp_sources" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach SSH (22) and RDP (3389). Empty denies management inbound."
}

variable "enable_flow_logs" {
  type        = bool
  default     = true
  description = "Enable NSG flow logs via a Network Watcher + storage account."
}

variable "tags" {
  type    = map(string)
  default = {}
}
