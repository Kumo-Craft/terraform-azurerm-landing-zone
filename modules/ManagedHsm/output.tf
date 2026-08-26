###############################################################
# MODULE: ManagedHsm - Outputs
###############################################################

output "id" {
  description = "The ID of the Managed HSM."
  value       = azurerm_key_vault_managed_hardware_security_module.this.id
}

output "name" {
  description = "The name of the Managed HSM."
  value       = azurerm_key_vault_managed_hardware_security_module.this.name
}

output "hsm_uri" {
  description = "The URI of the Managed HSM, used for data-plane key operations."
  value       = azurerm_key_vault_managed_hardware_security_module.this.hsm_uri
}

output "role_assignment_ids" {
  description = "Map of role_assignments key => local-RBAC role assignment ID (empty when none)."
  value       = { for k, r in azurerm_key_vault_managed_hardware_security_module_role_assignment.this : k => r.id }
}

output "lock_ids" {
  description = "Map of management lock IDs (empty when var.lock is null)."
  value       = module.lock.ids
}
