###############################################################
# MODULE: PolicyRemediation - Outputs
###############################################################

output "remediation_ids" {
  description = "Map of remediation task name => resource ID (across all 4 scopes — MG, Subscription, RG, Resource)."
  value = merge(
    { for k, v in azurerm_management_group_policy_remediation.this : k => v.id },
    { for k, v in azurerm_subscription_policy_remediation.this : k => v.id },
    { for k, v in azurerm_resource_group_policy_remediation.this : k => v.id },
    { for k, v in azurerm_resource_policy_remediation.this : k => v.id },
  )
}

output "remediation_names" {
  description = "Map of remediation task name => Azure-side resource name (passthrough of map keys for parity with sibling outputs)."
  value = {
    for k in keys(var.remediations) : k => k
  }
}
