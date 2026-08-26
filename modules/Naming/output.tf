###############################################################
# MODULE: Naming - Outputs
# Description: Single passthrough output exposing every per-type
#              naming output from Azure/naming/azurerm. Callers
#              pick the type they need:
#
#                module.naming.result.key_vault.name
#                module.naming.result.storage_account.name_unique
#                module.naming.result.container_registry.name
#
# Refer to the upstream module for the full list of supported
# Azure resource types: https://registry.terraform.io/modules/Azure/naming/azurerm/0.4.3
###############################################################

output "result" {
  description = "All per-resource-type naming outputs from Azure/naming/azurerm. Access as result.<type>.name (e.g. result.key_vault.name, result.resource_group.name, result.storage_account.name_unique)."
  value       = module.this
}

###############################################################
# Convenience outputs — the composed suffix and seed, useful for
# debugging or for modules that need the raw segments alongside
# the generated name.
###############################################################
output "suffix" {
  description = "The composed suffix list passed to the upstream module: [subscription_acronym, environment, region_code, workload, ...extra_suffix]."
  value       = tolist(local.suffix)
}

output "unique_seed" {
  description = "The effective unique_seed used by the upstream module (input override, or the joined suffix when null)."
  value       = local.effective_unique_seed
}
