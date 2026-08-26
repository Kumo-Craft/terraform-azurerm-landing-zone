###############################################################
# MODULE: AvdWorkspace - Outputs
###############################################################

output "id" {
  description = "Workspace resource ID"
  value       = azurerm_virtual_desktop_workspace.this.id
}

output "name" {
  description = "Workspace name"
  value       = azurerm_virtual_desktop_workspace.this.name
}

# F-5: full workspace resource object for downstream composition
output "resource" {
  description = "Full workspace resource object"
  value       = azurerm_virtual_desktop_workspace.this
}

# F-1: map of logical association name => association resource ID
output "association_ids" {
  description = "Map of logical association name => association resource ID"
  value       = { for k, v in azurerm_virtual_desktop_workspace_application_group_association.this : k => v.id }
}

# F-3: management lock ID (null if var.lock is null)
output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

# F-4: map of role assignment logical name => role assignment ID
output "role_assignment_ids" {
  description = "Map of role assignment logical name => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
