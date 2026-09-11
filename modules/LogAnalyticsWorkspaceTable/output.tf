###############################################################
# MODULE: LogAnalyticsWorkspaceTable - Outputs
###############################################################

output "table_ids" {
  description = "Map of table name => azurerm_log_analytics_workspace_table ID."
  value       = { for k, v in azurerm_log_analytics_workspace_table.this : k => v.id }
}

output "table_plans" {
  description = "Map of table name => effective plan."
  value       = { for k, v in azurerm_log_analytics_workspace_table.this : k => v.plan }
}
