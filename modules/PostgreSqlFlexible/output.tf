###############################################################
# MODULE: PostgreSqlFlexible - Outputs
###############################################################

output "id" {
  description = "The ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  description = "The name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "The fully qualified domain name of the server"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "identity_principal_id" {
  description = "Principal ID of the server managed identity (null if no identity block)."
  value       = try(azurerm_postgresql_flexible_server.this.identity[0].principal_id, null)
}

output "database_ids" {
  description = "Map of database key => database ID"
  value       = { for k, v in azurerm_postgresql_flexible_server_database.this : k => v.id }
}

output "private_endpoint_ids" {
  description = "Map of private endpoint key => Private Endpoint ID"
  value       = { for k, m in module.private_endpoint : k => m.ids[k] }
}

output "private_endpoint_ips" {
  description = "Map of private endpoint key => private IP address"
  value       = { for k, m in module.private_endpoint : k => m.private_ip_addresses[k] }
}

output "resource" {
  description = "The complete PostgreSQL Flexible Server resource object (sensitive: carries the admin password)."
  value       = azurerm_postgresql_flexible_server.this
  sensitive   = true
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment logical key => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
