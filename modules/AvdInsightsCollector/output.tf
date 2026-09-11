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

###############################################################
# Data Collection Endpoint
#
# dce_id is consumed OUTSIDE this landing zone: the platform scopes it
# into the shared AMPLS (management subscription). Without that scoping
# the endpoint doesn't resolve privately and the agent keeps failing
# GetConfig with 403 — treat this output as a published contract.
###############################################################
output "dce_id" {
  description = "Resource ID of the AVD Data Collection Endpoint. REQUIRED by the platform to scope the DCE into the shared AMPLS."
  value       = azurerm_monitor_data_collection_endpoint.avd.id
}

output "dce_name" {
  description = "Name of the AVD Data Collection Endpoint."
  value       = azurerm_monitor_data_collection_endpoint.avd.name
}

output "dce_configuration_access_endpoint" {
  description = "Configuration access URL the Azure Monitor Agent calls to retrieve its DCRs."
  value       = azurerm_monitor_data_collection_endpoint.avd.configuration_access_endpoint
}

output "configuration_access_association_ids" {
  description = "Map of session host resource ID => DCE (configurationAccessEndpoint) association ID (empty until session_host_ids is populated)."
  value       = { for k, v in azurerm_monitor_data_collection_rule_association.config_access : k => v.id }
}

output "lock_ids" {
  description = "Map of management lock IDs (empty when var.lock is null)."
  value       = module.lock.ids
}
