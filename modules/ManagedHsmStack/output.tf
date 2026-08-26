###############################################################
# MODULE: ManagedHsmStack - Outputs
###############################################################

output "resource_group_name" {
  description = "The name of the resource group (caller-provided)."
  value       = var.resource_group_name
}

###############################################################
# Managed HSM
###############################################################
output "hsm_id" {
  description = "The Managed HSM resource ID."
  value       = module.hsm.id
}

output "hsm_name" {
  description = "The Managed HSM name."
  value       = module.hsm.name
}

output "hsm_uri" {
  description = "The Managed HSM URI, used for data-plane key operations."
  value       = module.hsm.hsm_uri
}

output "hsm_lock_ids" {
  description = "Map of Managed HSM management lock IDs (empty when lock is null)."
  value       = module.hsm.lock_ids
}

output "hsm_role_assignment_ids" {
  description = "Map of role_assignments key => local-RBAC role assignment ID (empty when none)."
  value       = module.hsm.role_assignment_ids
}

###############################################################
# Backup identity (null when enable_backup_identity = false)
###############################################################
output "backup_identity_id" {
  description = "Resource ID of the backup UAMI (null when disabled). Associate it to the HSM via `az keyvault update-hsm --mi-user-assigned <this>`."
  value       = try(module.backup_identity[0].id, null)
}

output "backup_identity_principal_id" {
  description = "Principal (object) ID of the backup UAMI (null when disabled)."
  value       = try(module.backup_identity[0].principal_id, null)
}

output "backup_identity_client_id" {
  description = "Client ID of the backup UAMI (null when disabled)."
  value       = try(module.backup_identity[0].client_id, null)
}

###############################################################
# Private Endpoint
###############################################################
output "private_endpoint_id" {
  description = "The Private Endpoint resource ID."
  value       = module.pe.ids["this"]
}

output "private_endpoint_name" {
  description = "The Private Endpoint name."
  value       = module.pe.resources["this"].name
}

output "private_endpoint_ip" {
  description = "The private IP address of the Private Endpoint."
  value       = module.pe.private_ip_addresses["this"]
}
