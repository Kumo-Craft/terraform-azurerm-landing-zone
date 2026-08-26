###############################################################
# MODULE: SqlManagedInstance - Outputs
###############################################################

output "id" {
  description = "The ID of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.this.id
}

output "name" {
  description = "The name of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.this.name
}

output "fqdn" {
  description = "The fully qualified domain name of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.this.fqdn
}

output "dns_zone" {
  description = "The DNS zone the managed instance is in (used for partner/failover-group setups)."
  value       = azurerm_mssql_managed_instance.this.dns_zone
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity (null if no identity block)."
  value       = try(azurerm_mssql_managed_instance.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "Tenant ID of the managed identity (null if no identity block)."
  value       = try(azurerm_mssql_managed_instance.this.identity[0].tenant_id, null)
}

output "resource" {
  description = "The complete SQL Managed Instance resource object (sensitive: carries the admin password)."
  value       = azurerm_mssql_managed_instance.this
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
