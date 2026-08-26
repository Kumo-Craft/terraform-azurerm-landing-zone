###############################################################
# MODULE: ConsumptionBudget - Outputs
###############################################################

output "id" {
  description = "Resource ID of the budget."
  value       = azurerm_consumption_budget_resource_group.this.id
}

output "name" {
  description = "Full budget name."
  value       = azurerm_consumption_budget_resource_group.this.name
}

# Canonical full resource object (mirrors sibling modules).
output "resources" {
  description = "Full budget resource object."
  value       = azurerm_consumption_budget_resource_group.this
}

# Lock IDs (empty map when var.lock is null).
output "lock_ids" {
  description = "Map of lock key => management lock ID (empty map when var.lock is null)."
  value       = module.lock.ids
}
