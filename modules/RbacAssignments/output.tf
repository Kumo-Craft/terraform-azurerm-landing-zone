###############################################################
# MODULE: RbacAssignments - Outputs
###############################################################

output "group_assignment_ids" {
  description = "Map of key => role assignment ID for Entra ID groups"
  value       = { for k, v in azurerm_role_assignment.groups : k => v.id }
}

output "identity_assignment_ids" {
  description = "Map of key => role assignment ID for managed identities"
  value       = { for k, v in azurerm_role_assignment.identities : k => v.id }
}

output "group_resources" {
  description = "Map of key => complete role assignment object for groups"
  value       = azurerm_role_assignment.groups
}

output "identity_resources" {
  description = "Map of key => complete role assignment object for identities"
  value       = azurerm_role_assignment.identities
}

output "resources" {
  description = "Combined map of all role assignment resources (groups + identities merged by their map keys). Pattern: post-v0.2.74 canonical."
  value       = merge(azurerm_role_assignment.groups, azurerm_role_assignment.identities)
}
