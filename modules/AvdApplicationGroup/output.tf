###############################################################
# MODULE: AvdApplicationGroup - Outputs
###############################################################

output "id" {
  description = "Application group resource ID"
  value       = azurerm_virtual_desktop_application_group.this.id
}

output "name" {
  description = "Application group name"
  value       = azurerm_virtual_desktop_application_group.this.name
}

output "resource" {
  description = "Full application group resource object"
  value       = azurerm_virtual_desktop_application_group.this
}

output "application_ids" {
  description = "Map of application logical key => application resource ID (populated for RemoteApp groups only)"
  value       = { for k, v in azurerm_virtual_desktop_application.this : k => v.id }
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment logical name => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
