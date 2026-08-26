###############################################################
# MODULE: PrometheusCollector - Outputs
###############################################################

# F-13b: id alias for sibling convention (canonical output name).
output "id" {
  description = "DCR resource ID (alias for dcr_id, sibling convention)."
  value       = azurerm_monitor_data_collection_rule.prometheus.id
}

output "dcr_id" {
  description = "The ID of the Data Collection Rule"
  value       = azurerm_monitor_data_collection_rule.prometheus.id
}

output "dcr_name" {
  description = "The name of the Data Collection Rule"
  value       = azurerm_monitor_data_collection_rule.prometheus.name
}

output "resource" {
  description = "The complete Data Collection Rule resource object"
  value       = azurerm_monitor_data_collection_rule.prometheus
}

# F-3: ResourceLock composition output.
output "lock_id" {
  description = "Resource lock ID when var.lock is set, otherwise null."
  value       = try(module.lock.ids["this"], null)
}
