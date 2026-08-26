###############################################################
# MODULE: LogAnalyticsWorkspace - Outputs
#
# Explicit field list on purpose — never export the raw resource
# object (it surfaces provider-deprecated attributes as warnings;
# see the FlowLogs/KeyVault/StorageAccount curations).
###############################################################

output "id" {
  description = "Resource ID of the Log Analytics Workspace (use for AMPLS scoped services, DCR destinations, diagnostic settings)."
  value       = azurerm_log_analytics_workspace.this.id
}

output "name" {
  description = "Name of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.this.name
}

output "workspace_id" {
  description = "Workspace (customer) ID — GUID. Used by agents/connectors, not the ARM id."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "primary_shared_key" {
  description = "Primary shared key. Empty/unusable when local_authentication_enabled = false (the default)."
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "secondary_shared_key" {
  description = "Secondary shared key. Empty/unusable when local_authentication_enabled = false (the default)."
  value       = azurerm_log_analytics_workspace.this.secondary_shared_key
  sensitive   = true
}

output "lock_ids" {
  description = "Map of management lock IDs (empty when var.lock is null)."
  value       = module.lock.ids
}
