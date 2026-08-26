###############################################################
# MODULE: KeyVaultStack - Outputs
###############################################################

###############################################################
# Resource Group (passthrough)
# Kept for backward compatibility — Stack no longer owns the RG
# since v0.2.2, but Terragrunt callers consume this output.
# The RG id is not exposed because the Stack does not look it up
# (no data.azurerm_resource_group). Callers needing the id should
# get it from the upstream ../ResourceGroup module instance.
###############################################################
output "resource_group_name" {
  description = "The name of the resource group (caller-provided)."
  value       = var.resource_group_name
}

###############################################################
# Key Vault
###############################################################
output "key_vault_id" {
  description = "The Key Vault resource ID"
  value       = module.kv.id
}

output "key_vault_name" {
  description = "The Key Vault name"
  value       = module.kv.name
}

output "key_vault_uri" {
  description = "The Key Vault URI (e.g., https://kv-name.vault.azure.net/)"
  value       = module.kv.vault_uri
}

output "key_vault_tenant_id" {
  description = "The Key Vault tenant ID"
  value       = module.kv.tenant_id
}

output "key_vault_resource" {
  description = "The complete Key Vault resource object"
  value       = module.kv.resource
}

###############################################################
# Private Endpoint
###############################################################
output "private_endpoint_id" {
  description = "The Private Endpoint resource ID"
  value       = module.pe.ids["this"]
}

output "private_endpoint_name" {
  description = "The Private Endpoint name"
  value       = module.pe.resources["this"].name
}

output "private_endpoint_ip" {
  description = "The private IP address of the Private Endpoint"
  value       = module.pe.private_ip_addresses["this"]
}
