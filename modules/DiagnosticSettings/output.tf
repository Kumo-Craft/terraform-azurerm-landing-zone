###############################################################
# MODULE: DiagnosticSettings - Outputs
###############################################################

output "ids" {
  description = "Map of key => Diagnostic Setting ID"
  value       = { for k, v in azurerm_monitor_diagnostic_setting.this : k => v.id }
}

output "resources" {
  description = "Map of key => complete Diagnostic Setting resource object"
  value       = azurerm_monitor_diagnostic_setting.this
}
