###############################################################
# MODULE: Ampls - Outputs
###############################################################

output "id" {
  description = "The ID of the Azure Monitor Private Link Scope"
  value       = azurerm_monitor_private_link_scope.this.id
}

output "resource" {
  description = "The complete AMPLS resource object"
  value       = azurerm_monitor_private_link_scope.this
}

output "scoped_service_ids" {
  description = "Map of scoped service key => scoped service resource ID"
  value       = { for k, v in azurerm_monitor_private_link_scoped_service.this : k => v.id }
}

output "private_endpoint_id" {
  description = "The ID of the AMPLS private endpoint"
  value       = module.private_endpoint.ids["ampls"]
}

output "private_ip_address" {
  description = "The private IP address of the AMPLS private endpoint"
  value       = try(module.private_endpoint.private_ip_addresses["ampls"], null)
}

output "lock_id" {
  description = "The ID of the management lock, if applied"
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment key => role assignment ID"
  value       = { for k, m in module.rbac : k => m.id }
}
