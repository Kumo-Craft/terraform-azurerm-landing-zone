###############################################################
# MODULE: SqlDatabase - Outputs
###############################################################

output "server_id" {
  description = "The SQL logical server resource ID"
  value       = azurerm_mssql_server.this.id
}

output "server_name" {
  description = "The SQL logical server name"
  value       = azurerm_mssql_server.this.name
}

output "fully_qualified_domain_name" {
  description = "The fully qualified domain name of the SQL server (e.g. <name>.database.windows.net)"
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "identity_principal_id" {
  description = "The system-assigned managed identity principal ID of the SQL server (null when no system-assigned identity)."
  value       = try(azurerm_mssql_server.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "The tenant ID of the SQL server managed identity (null when no system-assigned identity)."
  value       = try(azurerm_mssql_server.this.identity[0].tenant_id, null)
}

output "auditing_policy_id" {
  description = "The SQL server extended auditing policy resource ID (null when no auditing destination was supplied)."
  value       = try(azurerm_mssql_server_extended_auditing_policy.this[0].id, null)
}

output "auditing_enabled" {
  description = "Whether server extended auditing was actually created (requires a Log Analytics workspace or storage endpoint)."
  value       = local.audit_enabled
}

output "database_ids" {
  description = "Map of database key => database resource ID."
  value       = { for k, db in azurerm_mssql_database.this : k => db.id }
}

output "database_names" {
  description = "Map of database key => database name."
  value       = { for k, db in azurerm_mssql_database.this : k => db.name }
}

output "server" {
  description = "The complete SQL logical server resource object."
  value       = azurerm_mssql_server.this
  sensitive   = true # contains administrator_login_password
}

output "databases" {
  description = "Map of database key => complete database resource object."
  value       = azurerm_mssql_database.this
  sensitive   = true # the full database object can carry provider-sensitive computed values
}

output "elastic_pool_ids" {
  description = "Map of elastic pool key => elastic pool resource ID."
  value       = { for k, p in azurerm_mssql_elasticpool.this : k => p.id }
}

output "elastic_pools" {
  description = "Map of elastic pool key => complete elastic pool resource object."
  value       = azurerm_mssql_elasticpool.this
  sensitive   = true
}

output "private_endpoint_ids" {
  description = "Map of private endpoint key => Private Endpoint resource ID."
  value       = { for k, m in module.private_endpoint : k => m.ids[k] }
}

output "private_endpoint_ip_addresses" {
  description = "Map of private endpoint key => assigned private IP address."
  value       = { for k, m in module.private_endpoint : k => m.private_ip_addresses[k] }
}
