output "vpc_id" {
  value       = aws_vpc.this.id
  description = "The VPC ID."
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value       = { for az, s in aws_subnet.public : az => s.id }
  description = "Map of AZ to public subnet ID."
}

output "private_subnet_ids" {
  value       = { for az, s in aws_subnet.private : az => s.id }
  description = "Map of AZ to private subnet ID."
}

output "nat_gateway_ids" {
  value = { for az, n in aws_nat_gateway.this : az => n.id }
}

output "flow_log_group" {
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow[0].name : null
  description = "CloudWatch Logs group for VPC flow logs, if enabled."
}
