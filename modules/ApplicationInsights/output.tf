###############################################################
# MODULE: ApplicationInsights - Outputs
###############################################################

output "id" {
  description = "The ID of the Application Insights component"
  value       = azurerm_application_insights.this.id
}

output "name" {
  description = "The name of the Application Insights component"
  value       = azurerm_application_insights.this.name
}

output "app_id" {
  description = "The Application ID (app_id) of the Application Insights component"
  value       = azurerm_application_insights.this.app_id
}

output "connection_string" {
  description = "The connection string of the Application Insights component (preferred over the instrumentation key)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "instrumentation_key" {
  description = "The instrumentation key of the Application Insights component (legacy; prefer connection_string)."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "resource" {
  description = "The complete Application Insights resource object"
  value       = azurerm_application_insights.this
  sensitive   = true
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment logical key => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
