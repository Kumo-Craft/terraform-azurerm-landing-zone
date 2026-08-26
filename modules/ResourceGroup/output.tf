###############################################################
# MODULE: ResourceGroup - Outputs
###############################################################

output "resource_groups" {
  description = "Map of created resource groups keyed by the input map key. Each value: { id, name, location, tags }."
  value = {
    for k, rg in azurerm_resource_group.this :
    k => {
      id       = rg.id
      name     = rg.name
      location = rg.location
      tags     = rg.tags
    }
  }
}

output "ids" {
  description = "Map of resource group IDs keyed by the input map key. Convenience for `dependency.rg.outputs.ids[\"network\"]`."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.id }
}

output "names" {
  description = "Map of resource group names keyed by the input map key."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.name }
}

output "locations" {
  description = "Map of resource group locations keyed by the input map key."
  value       = { for k, rg in azurerm_resource_group.this : k => rg.location }
}

output "resources" {
  description = "Full azurerm_resource_group resource objects, keyed by input map key."
  value       = azurerm_resource_group.this
}

output "role_assignment_ids" {
  description = "Map of role assignment keys (\"<rg_key>|<ra_key>\") to their Azure resource IDs."
  value       = { for k, ra in module.role_assignments : k => ra.id }
}
