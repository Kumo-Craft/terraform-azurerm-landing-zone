###############################################################
# MODULE: KeyVaultSecrets - Outputs
###############################################################

output "secret_ids" {
  description = "Map of secret key => Key Vault secret resource ID"
  value       = { for k, v in azurerm_key_vault_secret.this : k => v.id }
}

output "secret_versionless_ids" {
  description = "Map of secret key => versionless ID (useful for VM CSE to pull latest)"
  value       = { for k, v in azurerm_key_vault_secret.this : k => v.versionless_id }
}
