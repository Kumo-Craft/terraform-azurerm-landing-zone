###############################################################
# MODULE: PolicyExemption - Outputs
###############################################################

output "ids" {
  description = "Map of exemption key to resource ID (merged across all scopes)."
  value = merge(
    { for k, v in azurerm_resource_group_policy_exemption.this : k => v.id },
    { for k, v in azurerm_subscription_policy_exemption.this : k => v.id },
    { for k, v in azurerm_management_group_policy_exemption.this : k => v.id },
  )
}

output "names" {
  description = "Map of exemption key to resource name (merged across all scopes)."
  value = merge(
    { for k, v in azurerm_resource_group_policy_exemption.this : k => v.name },
    { for k, v in azurerm_subscription_policy_exemption.this : k => v.name },
    { for k, v in azurerm_management_group_policy_exemption.this : k => v.name },
  )
}
