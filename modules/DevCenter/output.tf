###############################################################
# MODULE: DevCenter - Outputs
###############################################################

output "id" {
  description = "The Dev Center resource ID"
  value       = azurerm_dev_center.this.id
}

output "name" {
  description = "The Dev Center name"
  value       = azurerm_dev_center.this.name
}

output "dev_center_uri" {
  description = "The URI of the Dev Center"
  value       = azurerm_dev_center.this.dev_center_uri
}

output "identity_principal_id" {
  description = "The system-assigned managed identity principal ID (null when no system-assigned identity). Grant this RBAC on catalogs, Key Vault, and deployment subscriptions."
  value       = try(azurerm_dev_center.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "The tenant ID of the Dev Center managed identity (null when no system-assigned identity)."
  value       = try(azurerm_dev_center.this.identity[0].tenant_id, null)
}

output "environment_type_ids" {
  description = "Map of environment type name => Dev Center Environment Type resource ID."
  value       = { for k, et in azurerm_dev_center_environment_type.this : k => et.id }
}

output "resource" {
  description = "The complete Dev Center resource object"
  value       = azurerm_dev_center.this
}
