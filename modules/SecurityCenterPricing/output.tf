###############################################################
# MODULE: SecurityCenterPricing - Outputs
#
# Explicit fields on purpose — no raw resource-object output (exporting
# the whole object surfaces any provider-deprecated attribute as a plan
# warning; house convention since the FlowLogs/KeyVault/StorageAccount
# curations).
###############################################################

output "enabled_plans" {
  description = "Map resource_type => \"tier\" ou \"tier/subplan\" des plans configurés."
  value = {
    for k, r in azurerm_security_center_subscription_pricing.this :
    # null-safe: coalesce(null, "") errors (both empty), so test explicitly.
    k => (r.subplan != null && r.subplan != "") ? "${r.tier}/${r.subplan}" : r.tier
  }
}

output "plan_ids" {
  description = "Map resource_type => resource ID du plan (/subscriptions/../providers/Microsoft.Security/pricings/<type>)."
  value       = { for k, r in azurerm_security_center_subscription_pricing.this : k => r.id }
}
