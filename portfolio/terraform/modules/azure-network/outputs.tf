output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  value       = { for k, s in azurerm_subnet.this : k => s.id }
  description = "Map of subnet name to subnet ID."
}

output "nsg_id" {
  value = azurerm_network_security_group.this.id
}
