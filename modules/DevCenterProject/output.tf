###############################################################
# MODULE: DevCenterProject - Outputs
###############################################################

output "id" {
  description = "The Dev Center Project resource ID"
  value       = azurerm_dev_center_project.this.id
}

output "name" {
  description = "The Dev Center Project name"
  value       = azurerm_dev_center_project.this.name
}

output "dev_center_uri" {
  description = "The URI of the Dev Center this project is associated with"
  value       = azurerm_dev_center_project.this.dev_center_uri
}

output "identity_principal_id" {
  description = "The system-assigned managed identity principal ID of the project (null when no system-assigned identity). Grant it RBAC on deployment subscriptions / project catalogs."
  value       = try(azurerm_dev_center_project.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "The tenant ID of the project managed identity (null when no system-assigned identity)."
  value       = try(azurerm_dev_center_project.this.identity[0].tenant_id, null)
}

output "resource" {
  description = "The complete Dev Center Project resource object"
  value       = azurerm_dev_center_project.this
}

output "environment_type_ids" {
  description = "Map of environment type name => Dev Center Project Environment Type resource ID."
  value       = { for k, et in azurerm_dev_center_project_environment_type.this : k => et.id }
}

output "environment_type_identity_principal_ids" {
  description = "Map of environment type name => deployment identity principal ID (null when no system-assigned identity). Grant Contributor + User Access Administrator on the target subscription."
  value       = { for k, et in azurerm_dev_center_project_environment_type.this : k => try(et.identity[0].principal_id, null) }
}
