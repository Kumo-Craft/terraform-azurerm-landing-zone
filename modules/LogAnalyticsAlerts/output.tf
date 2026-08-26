###############################################################
# MODULE: LogAnalyticsAlerts - Outputs
###############################################################

output "alert_ids" {
  description = "Map of alert key -> resource ID."
  value       = { for k, r in azurerm_monitor_scheduled_query_rules_alert_v2.this : k => r.id }
}

output "alert_names" {
  description = "Map of alert key -> full resource name."
  value       = { for k, r in azurerm_monitor_scheduled_query_rules_alert_v2.this : k => r.name }
}

# F-8: canonical full resource object map (mirrors sibling modules).
output "resources" {
  description = "Full map of alert rule resource objects keyed by var.alerts logical name."
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.this
}

###############################################################
# DCR / DCE outputs - consumed by CI/CD pipelines that ingest
# events via the Logs Ingestion API. Null when no `ingestion`
# block is declared on any custom table.
###############################################################

output "data_collection_endpoint_id" {
  description = "Resource ID of the Data Collection Endpoint (null if no ingestion configured)."
  value       = length(azurerm_monitor_data_collection_endpoint.this) > 0 ? azurerm_monitor_data_collection_endpoint.this[0].id : null
}

output "data_collection_endpoint_logs_ingestion_endpoint" {
  description = "Host used by Logs Ingestion API clients (e.g. https://<dce>.<region>.ingest.monitor.azure.com)."
  value       = length(azurerm_monitor_data_collection_endpoint.this) > 0 ? azurerm_monitor_data_collection_endpoint.this[0].logs_ingestion_endpoint : null
}

output "data_collection_rule_id" {
  description = "Resource ID of the Data Collection Rule (null if no ingestion configured)."
  value       = length(azurerm_monitor_data_collection_rule.this) > 0 ? azurerm_monitor_data_collection_rule.this[0].id : null
}

output "data_collection_rule_immutable_id" {
  description = "Immutable ID of the DCR - required in the Logs Ingestion API URL path."
  value       = length(azurerm_monitor_data_collection_rule.this) > 0 ? azurerm_monitor_data_collection_rule.this[0].immutable_id : null
}

output "dcr_stream_names" {
  description = "Map of custom-table key -> DCR stream name to POST to (Custom-<Table>_CL)."
  value       = { for k, _ in local.ingestion_tables : k => "Custom-${k}_CL" }
}

# F-13: lock IDs per alert rule (empty map when var.lock is null).
output "lock_ids" {
  description = "Map of alert key => management lock ID (empty map when var.lock is null)."
  value       = module.lock.ids
}
