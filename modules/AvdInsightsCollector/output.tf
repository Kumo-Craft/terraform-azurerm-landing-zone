###############################################################
# MODULE: AvdInsightsCollector - Outputs
#
# Explicit field list — no raw `resource` output (exporting the whole
# object surfaces provider-deprecated attributes as plan warnings).
###############################################################

output "id" {
  description = "Resource ID of the AVD Insights Data Collection Rule."
  value       = azurerm_monitor_data_collection_rule.avd.id
}

output "name" {
  description = "Name of the AVD Insights Data Collection Rule."
  value       = azurerm_monitor_data_collection_rule.avd.name
}

output "association_ids" {
  description = "Map of session host resource ID => DCR association ID (empty until session_host_ids is populated)."
  value       = { for k, v in azurerm_monitor_data_collection_rule_association.avd : k => v.id }
}

output "lock_ids" {
  description = "Map of management lock IDs (empty when var.lock is null)."
  value       = module.lock.ids
}
