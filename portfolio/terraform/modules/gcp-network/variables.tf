variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "name" {
  type        = string
  description = "Name prefix (e.g. prod)."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "subnets" {
  type = map(object({
    cidr                  = string
    region                = optional(string)
    private_google_access = optional(bool, true)
    secondary_ranges      = optional(map(string), {}) # name => cidr (for GKE pods/services)
  }))
  description = "Subnets by name."
}

variable "allowed_ssh_sources" {
  type        = list(string)
  default     = ["35.235.240.0/20"] # Google IAP range; replace with your management CIDRs
  description = "Sources allowed to SSH (22). Defaults to the IAP range."
}

variable "enable_cloud_nat" {
  type        = bool
  default     = true
  description = "Create a Cloud Router + Cloud NAT so instances without public IPs reach the internet."
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}
