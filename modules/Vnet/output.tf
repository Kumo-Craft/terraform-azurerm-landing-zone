###############################################################
# MODULE: Vnet - Outputs
###############################################################

output "id" {
  description = "The VNet resource ID"
  value       = azurerm_virtual_network.this.id
}

output "name" {
  description = "The VNet name"
  value       = azurerm_virtual_network.this.name
}

output "resource_group_name" {
  description = "The VNet resource group name"
  value       = azurerm_virtual_network.this.resource_group_name
}

output "location" {
  description = "The VNet Azure region"
  value       = azurerm_virtual_network.this.location
}

output "tags" {
  description = "The tags applied to the VNet"
  value       = azurerm_virtual_network.this.tags
}

output "resource" {
  description = "The complete Virtual Network resource object"
  value       = azurerm_virtual_network.this
}

output "role_assignment_ids" {
  description = "Map of role assignment logical key => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}

###############################################################
# Subnet Outputs (empty maps when subnets = [])
###############################################################
output "subnet_ids" {
  description = "Map of subnet name => subnet ID"
  value       = { for k, s in azapi_resource.subnet : k => s.id }
}

output "subnet_names" {
  description = "Map of subnet name => subnet name"
  value       = { for k, s in azapi_resource.subnet : k => s.name }
}
