###############################################################
# MODULE: PrometheusAlertRules - Outputs
###############################################################

output "ids" {
  description = "Map of rule group key to resource ID"
  value       = { for k, v in azurerm_monitor_alert_prometheus_rule_group.this : k => v.id }
}

output "names" {
  description = "Map of rule group key to resource name"
  value       = { for k, v in azurerm_monitor_alert_prometheus_rule_group.this : k => v.name }
}

# M-6: full resource object for downstream composition.
output "rule_groups" {
  description = "Map of alert rule group key => full resource object"
  value       = azurerm_monitor_alert_prometheus_rule_group.this
}

# I-4: lock IDs per rule group (empty map when var.lock is null).
output "lock_ids" {
  description = "Map of rule group key => management lock ID (empty map when var.lock is null)"
  value       = module.lock.ids
}
