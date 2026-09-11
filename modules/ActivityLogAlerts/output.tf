###############################################################
# MODULE: ActivityLogAlerts - Outputs
###############################################################

output "ids" {
  description = "Map of alert key => activity log alert ID."
  value       = { for k, v in azurerm_monitor_activity_log_alert.this : k => v.id }
}

output "names" {
  description = "Map of alert key => full resource name ({base}-{key})."
  value       = { for k, v in azurerm_monitor_activity_log_alert.this : k => v.name }
}

output "resources" {
  description = "Map of alert key => complete resource object."
  value       = azurerm_monitor_activity_log_alert.this
}

output "lock_ids" {
  description = "Map of alert key => management lock ID ({} if var.lock is null)."
  value       = module.lock.ids
}
