###############################################################
# MODULE: KeyVault-Key - Outputs
###############################################################

output "keys" {
  description = "Full azurerm_key_vault_key resources by map key"
  value       = azurerm_key_vault_key.this
}

output "ids" {
  description = "Map of key map key => versioned Key ID"
  value       = { for k, v in azurerm_key_vault_key.this : k => v.id }
}

output "versionless_ids" {
  description = "Map of key map key => versionless Key ID (for CMK auto-rotation consumers)"
  value       = { for k, v in azurerm_key_vault_key.this : k => v.versionless_id }
}

output "names" {
  description = "Map of key map key => key name"
  value       = { for k, v in azurerm_key_vault_key.this : k => v.name }
}
