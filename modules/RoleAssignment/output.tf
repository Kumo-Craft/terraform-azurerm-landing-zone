###############################################################
# MODULE: RoleAssignment - Outputs
###############################################################

output "id" {
  description = "Resource ID of the role assignment."
  value       = azurerm_role_assignment.this.id
}

output "name" {
  description = "Name (GUID) of the role assignment."
  value       = azurerm_role_assignment.this.name
}

output "role_definition_id" {
  description = "Resolved role_definition_id passed to azurerm_role_assignment (null if the assignment uses role_definition_name)."
  value       = azurerm_role_assignment.this.role_definition_id
}

output "role_definition_name" {
  description = "Resolved role_definition_name passed to azurerm_role_assignment (null if the assignment uses role_definition_id)."
  value       = azurerm_role_assignment.this.role_definition_name
}

output "principal_id" {
  description = "Principal object ID receiving the role."
  value       = azurerm_role_assignment.this.principal_id
}

output "principal_type" {
  description = "Resolved principal type (User, Group, ServicePrincipal, …) of the assignment."
  value       = azurerm_role_assignment.this.principal_type
}

output "scope" {
  description = "Scope at which the role is granted."
  value       = azurerm_role_assignment.this.scope
}
