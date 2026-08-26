###############################################################
# MODULE: ManagedIdentity - Outputs
###############################################################

output "id" {
  description = "Managed identity ID"
  value       = azurerm_user_assigned_identity.this.id
}

output "name" {
  description = "Managed identity name"
  value       = azurerm_user_assigned_identity.this.name
}

output "principal_id" {
  description = "Identity principal ID (object ID)"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "Identity client ID (application ID)"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  description = "Tenant ID"
  value       = azurerm_user_assigned_identity.this.tenant_id
}

output "resource" {
  description = "The complete User Assigned Identity resource object"
  value       = azurerm_user_assigned_identity.this
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

output "federated_credential_ids" {
  description = "Map of federated credential logical key => resource ID"
  value       = { for k, v in azurerm_federated_identity_credential.this : k => v.id }
}

output "role_assignment_ids" {
  description = "Map of role assignment logical key => role assignment ID"
  value       = { for k, v in module.role_assignments : k => v.id }
}
