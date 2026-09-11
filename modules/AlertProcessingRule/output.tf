###############################################################
# MODULE: AlertProcessingRule - Outputs
###############################################################

output "id" {
  description = "The ID of the Alert Processing Rule."
  value       = azurerm_monitor_alert_processing_rule_action_group.this.id
}

output "name" {
  description = "The name of the Alert Processing Rule."
  value       = azurerm_monitor_alert_processing_rule_action_group.this.name
}

output "resource" {
  description = "The complete Alert Processing Rule resource object."
  value       = azurerm_monitor_alert_processing_rule_action_group.this
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)."
  value       = try(module.lock.ids["this"], null)
}
