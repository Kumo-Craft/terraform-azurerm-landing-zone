output "set_definition_ids" {
  description = "Map of set definition name => Azure resource ID. Use as input to PolicyAssignment.assignments[].policy_definition_id when assigning an initiative."
  value = merge(
    { for k, v in azurerm_policy_set_definition.this : k => v.id },
    { for k, v in azurerm_management_group_policy_set_definition.this : k => v.id }
  )
}

output "set_definition_names" {
  description = "Map of set definition name => Azure-side resource name (map key passthrough)."
  value       = { for k in keys(var.set_definitions) : k => k }
}

output "policy_definition_reference_ids" {
  description = "Map of set definition name => map of member reference_id => the full reference object. Useful for PolicyExemption/PolicyRemediation targeting specific initiative members."
  value = {
    for k, v in var.set_definitions : k => {
      for ref in v.policy_definition_references : ref.reference_id => ref
      if ref.reference_id != null
    }
  }
}
