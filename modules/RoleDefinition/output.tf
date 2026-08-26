###############################################################
# MODULE: RoleDefinition - Outputs
###############################################################

output "role_definition_resource_id" {
  description = "Fully-qualified Azure Resource Manager ID of the role — pass this to azurerm_role_assignment.role_definition_id."
  value       = azurerm_role_definition.this.role_definition_resource_id
}

output "role_definition_id" {
  description = "GUID (roleDefinitionId) of the custom role."
  value       = azurerm_role_definition.this.role_definition_id
}

output "name" {
  description = "Display name of the custom role."
  value       = azurerm_role_definition.this.name
}

output "assignable_scopes" {
  description = "Effective assignable scopes of the role."
  value       = azurerm_role_definition.this.assignable_scopes
}

output "assignment_ids" {
  description = "Map of the created role-assignment resource IDs, keyed by \"<principal_id>|<scope>\"."
  value       = { for k, m in module.assignment : k => m.id }
}
