output "resource" {
  description = "Full ALZ architecture module output object"
  value       = module.alz_architecture
}

output "management_group_ids" {
  description = "Map of management group IDs"
  value       = module.alz_architecture.management_group_resource_ids
}

output "policy_assignment_identity_ids" {
  description = "Map of policy assignment identity principal IDs"
  value       = module.alz_architecture.policy_assignment_identity_ids
}

output "policy_assignment_resource_ids" {
  description = "Map of policy assignment name => resource ID (consumed by downstream PolicyExemption / PolicyRemediation modules at the LZ scope)."
  value       = module.alz_architecture.policy_assignment_resource_ids
}

output "policy_definition_resource_ids" {
  description = "Map of policy definition name => resource ID."
  value       = module.alz_architecture.policy_definition_resource_ids
}
