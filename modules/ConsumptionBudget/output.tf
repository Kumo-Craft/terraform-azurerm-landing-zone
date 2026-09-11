###############################################################
# MODULE: ConsumptionBudget - Outputs
# Scope-agnostic: id/name resolve to whichever budget exists
# (RG or subscription). The two object outputs are null for the
# scope that isn't used (count = 0) — nothing breaks either way.
###############################################################

output "id" {
  description = "Resource ID of the budget (whichever scope is in use)."
  value       = local.budget_id
}

output "name" {
  description = "Full budget name."
  value       = local.budget_name
}

# Resource-group budget object (null when subscription-scoped).
# Backward-compatible: RG-scope consumers keep reading `resources`.
output "resources" {
  description = "The resource-group budget object (null when subscription-scoped)."
  value       = one(azurerm_consumption_budget_resource_group.this[*])
}

# Subscription budget object (null when RG-scoped).
output "subscription_budget" {
  description = "The subscription budget object (null when RG-scoped)."
  value       = one(azurerm_consumption_budget_subscription.this[*])
}

# Lock IDs (empty map when var.lock is null).
output "lock_ids" {
  description = "Map of lock key => management lock ID (empty map when var.lock is null)."
  value       = module.lock.ids
}
