###############################################################
# MODULE: AvdScalingPlan - Outputs
###############################################################

output "id" {
  description = "Scaling plan resource ID"
  value       = azurerm_virtual_desktop_scaling_plan.this.id
}

output "name" {
  description = "Scaling plan name"
  value       = azurerm_virtual_desktop_scaling_plan.this.name
}

# F-1: full scaling plan resource object for downstream composition.
output "resource" {
  description = "Full scaling plan resource object"
  value       = azurerm_virtual_desktop_scaling_plan.this
}

# F-2: management lock ID (null if var.lock is null).
output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

# F-3: map of role assignment logical name => role assignment ID.
output "role_assignment_ids" {
  description = "Map of role assignment logical name => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
