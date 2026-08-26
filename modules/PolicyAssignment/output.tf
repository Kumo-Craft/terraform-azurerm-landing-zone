###############################################################
# MODULE: PolicyAssignment - Outputs
###############################################################

output "assignment_ids" {
  description = "Map of assignment name => resource ID (across all scopes)."
  value = merge(
    { for k, v in azurerm_resource_group_policy_assignment.this : k => v.id },
    { for k, v in azurerm_subscription_policy_assignment.this : k => v.id },
    { for k, v in azurerm_management_group_policy_assignment.this : k => v.id },
  )
}

output "identity_principal_ids" {
  description = "Map of assignment name => managed identity principal ID. SystemAssigned: populated after first apply. UserAssigned: null (the provider does not expose UAMI principal_id on policy assignments — use the UAMI's own principal_id from the ManagedIdentity module instead)."
  value = merge(
    { for k, v in azurerm_resource_group_policy_assignment.this : k => try(v.identity[0].principal_id, null) if length(v.identity) > 0 },
    { for k, v in azurerm_subscription_policy_assignment.this : k => try(v.identity[0].principal_id, null) if length(v.identity) > 0 },
    { for k, v in azurerm_management_group_policy_assignment.this : k => try(v.identity[0].principal_id, null) if length(v.identity) > 0 },
  )
}

output "role_assignment_ids" {
  description = "Map of \"<assignment_key>-<index>\" => role assignment resource ID created by the inline role_assignments wiring. Empty when no role_assignments are configured."
  value       = { for k, v in module.policy_identity : k => v.id }
}

output "compliance_query_urls" {
  description = "Map of assignment name => Azure Policy compliance API query URL (REST GET). Useful for audit scripts and external compliance dashboards."
  value = {
    for k, v in merge(
      { for k, v in azurerm_resource_group_policy_assignment.this : k => v.id },
      { for k, v in azurerm_subscription_policy_assignment.this : k => v.id },
      { for k, v in azurerm_management_group_policy_assignment.this : k => v.id },
    ) : k => "https://management.azure.com${v}/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2019-10-01"
  }
}
