output "definition_ids" {
  description = "Map of definition name => Azure resource ID. Use as input to PolicySetDefinition.set_definitions[].policy_definition_references[].policy_definition_id or PolicyAssignment.assignments[].policy_definition_id."
  value       = { for k, v in azurerm_policy_definition.this : k => v.id }
}

output "definition_names" {
  description = "Map of definition name => Azure-side resource name (map key passthrough)."
  value       = { for k in keys(var.definitions) : k => k }
}
