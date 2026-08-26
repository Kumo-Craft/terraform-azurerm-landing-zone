###############################################################
# MODULE: ResourceLock - Outputs
###############################################################

output "ids" {
  description = "Map of lock key => lock ID"
  value       = { for k, v in azurerm_management_lock.this : k => v.id }
}

output "resources" {
  description = "Map of lock key => complete lock resource object"
  value       = azurerm_management_lock.this
}
