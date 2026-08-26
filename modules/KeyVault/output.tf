###############################################################
# MODULE: KeyVault - Outputs
###############################################################

output "id" {
  description = "The Key Vault resource ID"
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "The Key Vault name"
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "The Key Vault URI (e.g., https://kv-name.vault.azure.net/). Mirrors azurerm_key_vault.vault_uri — preferred over the legacy `uri` output."
  value       = azurerm_key_vault.this.vault_uri
}

output "uri" {
  description = "DEPRECATED — use `vault_uri` instead. Kept for backwards compatibility with existing callers; will be removed in a future major version."
  value       = azurerm_key_vault.this.vault_uri
}

output "tenant_id" {
  description = "The Key Vault tenant ID"
  value       = azurerm_key_vault.this.tenant_id
}

output "resource" {
  description = "Curated Key Vault attributes for downstream composition/inspection. Explicit field list (not the raw resource object) to avoid surfacing the provider-deprecated `contact` block — moved to the azurerm_key_vault_certificate_contacts resource. Same pattern as FlowLogs #10939."
  value = {
    id                  = azurerm_key_vault.this.id
    name                = azurerm_key_vault.this.name
    vault_uri           = azurerm_key_vault.this.vault_uri
    tenant_id           = azurerm_key_vault.this.tenant_id
    location            = azurerm_key_vault.this.location
    resource_group_name = azurerm_key_vault.this.resource_group_name
  }
}
