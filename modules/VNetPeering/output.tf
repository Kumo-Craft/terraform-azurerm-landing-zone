###############################################################
# MODULE: VNetPeering - Outputs
###############################################################

output "ids" {
  description = "Map of peering key => peering ID"
  value       = { for k, v in azurerm_virtual_network_peering.this : k => v.id }
}

output "resources" {
  description = "Map of peering key => complete peering resource object"
  value       = azurerm_virtual_network_peering.this
}
