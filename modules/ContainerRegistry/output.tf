###############################################################
# MODULE: ContainerRegistry - Outputs
###############################################################

output "id" {
  description = "Container Registry ID"
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Container Registry name"
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Login server URL (e.g. crapiprodgwc001.azurecr.io)"
  value       = azurerm_container_registry.this.login_server
}

output "private_endpoint_ids" {
  description = "Map of private endpoint key => Private Endpoint resource ID."
  value       = { for k, m in module.private_endpoint : k => m.ids[k] }
}

output "private_endpoint_ip_addresses" {
  description = "Map of private endpoint key => assigned private IP address."
  value       = { for k, m in module.private_endpoint : k => m.private_ip_addresses[k] }
}

output "resource" {
  # sensitive=true because azurerm_container_registry embeds admin_password
  # (computed+sensitive in azurerm 4.75.0 schema — present in state even when
  # admin_enabled=false as null-but-schema-present). 5th repo-wide application
  # of Truth 6 (TlsSelfSignedCert v0.2.64 F-4 + Vm-Windows v0.2.71 F-8 +
  # PaloCluster v0.2.74 F-10 + ApplicationGateway v0.2.81 F-3 +
  # ContainerRegistry v0.2.83 F-3).
  description = "The complete Container Registry resource object"
  value       = azurerm_container_registry.this
  sensitive   = true
}
