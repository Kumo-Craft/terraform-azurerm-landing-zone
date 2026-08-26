###############################################################
# MODULE: NetworkWatcher - Outputs
###############################################################

output "id" {
  description = "The ID of the Network Watcher"
  value       = azurerm_network_watcher.this.id
}

output "name" {
  description = "The name of the Network Watcher"
  value       = azurerm_network_watcher.this.name
}

output "resource" {
  description = "The complete Network Watcher resource object"
  value       = azurerm_network_watcher.this
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = var.resource_group_name
}
