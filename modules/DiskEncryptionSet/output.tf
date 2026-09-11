###############################################################
# MODULE: DiskEncryptionSet - Outputs
###############################################################

output "id" {
  description = "Disk Encryption Set resource ID. Feed it to a disk's disk_encryption_set_id — but depend on role_assignment_id, not this, so the key grant lands first."
  value       = azurerm_disk_encryption_set.this.id
}

output "name" {
  description = "Disk Encryption Set name."
  value       = azurerm_disk_encryption_set.this.name
}

output "principal_id" {
  description = "Principal ID of the DES managed identity — the one that must hold key access on the vault."
  value       = azurerm_disk_encryption_set.this.identity[0].principal_id
}

# The dependency edge that matters. A disk attached to a DES whose
# identity cannot unwrap the key fails AT THE DISK, with an error that
# says nothing about RBAC. Callers should reference this output (even
# just in depends_on) rather than `id` alone.
output "role_assignment_id" {
  description = "Key Vault role assignment ID granting the DES identity 'Key Vault Crypto Service Encryption User'. null when key_vault_id was not supplied (grant made out-of-band). Depend on this before attaching disks."
  value       = try(module.key_access["this"].id, null)
}

output "key_vault_key_url" {
  description = "The key URL the DES actually resolved. With auto key rotation this follows the current version — useful to confirm rotation is being tracked."
  value       = azurerm_disk_encryption_set.this.key_vault_key_url
}
