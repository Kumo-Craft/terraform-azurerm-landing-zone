###############################################################
# MODULE: SecurityCenterSubscription - Outputs
###############################################################

output "id" {
  description = "The ID of the security contact (.../providers/Microsoft.Security/securityContacts/default)."
  value       = azapi_resource.this.id
}

output "name" {
  description = "The security contact name — always \"default\" (Azure allows only one, under this name)."
  value       = azapi_resource.this.name
}

output "email" {
  description = "The configured security contact email(s) (properties.emails)."
  value       = var.email
}

output "notifications_sources" {
  description = "The effective notificationsSources[] written to the contact (empty list when none declared)."
  value       = local.notifications_sources
}
