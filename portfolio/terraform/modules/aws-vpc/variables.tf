variable "name" {
  type        = string
  description = "Name prefix for all resources (e.g. prod, shared-services)."
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block, e.g. 10.40.0.0/16."
  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && tonumber(split("/", var.cidr_block)[1]) <= 24
    error_message = "cidr_block must be valid CIDR with prefix /24 or larger (smaller number)."
  }
}

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of Availability Zones to spread subnets across (2 or 3)."
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 for resilient designs."
  }
}

variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Create NAT gateways so private subnets reach the internet outbound."
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "Use one NAT gateway for all AZs (cheaper, not HA). Ignored unless enable_nat_gateway."
}

variable "enable_flow_logs" {
  type        = bool
  default     = true
  description = "Send VPC flow logs to CloudWatch Logs for network visibility and audits."
}

variable "flow_log_retention_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
