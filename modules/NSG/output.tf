###############################################################
# MODULE: NSG - Outputs
###############################################################

output "ids" {
  description = "Map of workload key => NSG ID"
  value       = { for k, v in azurerm_network_security_group.this : k => v.id }
}

output "names" {
  description = "Map of workload key => NSG name"
  value       = { for k, v in azurerm_network_security_group.this : k => v.name }
}

output "resources" {
  description = "Map of workload key => complete NSG resource object"
  value       = azurerm_network_security_group.this
}
