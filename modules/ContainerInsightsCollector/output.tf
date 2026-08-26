###############################################################
# MODULE: ContainerInsightsCollector - Outputs
###############################################################

# Canonical id alias (sibling convention).
output "id" {
  description = "DCR resource ID (alias for dcr_id, sibling convention)."
  value       = azurerm_monitor_data_collection_rule.ci.id
}

output "dcr_id" {
  description = "Resource ID of the Container Insights Data Collection Rule."
  value       = azurerm_monitor_data_collection_rule.ci.id
}

output "dcr_name" {
  description = "Name of the Container Insights Data Collection Rule."
  value       = azurerm_monitor_data_collection_rule.ci.name
}

output "dcra_id" {
  description = "Resource ID of the DCR association on the AKS cluster."
  value       = azurerm_monitor_data_collection_rule_association.ci.id
}

# F-5: Canonical resource output. No sensitive=true — DCR has no sensitive
# computed attributes (Truth 6 N/A for this resource type).
output "resource" {
  description = "The azurerm_monitor_data_collection_rule resource (DCR routing Container Insights streams)."
  value       = azurerm_monitor_data_collection_rule.ci
}

# F-3: ResourceLock composition output.
output "lock_id" {
  description = "Resource lock ID when var.lock is set, otherwise null."
  value       = try(module.lock.ids["this"], null)
}

# F-4: RoleAssignment composition output.
output "role_assignment_ids" {
  description = "Map of role assignment IDs keyed by the var.role_assignments map key."
  value       = { for k, v in module.role_assignments : k => v.id }
}
