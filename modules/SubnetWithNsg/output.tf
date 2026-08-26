###############################################################
# MODULE: SubnetWithNsg - Outputs
###############################################################

output "subnet_ids" {
  description = "Map of subnet name => subnet ID"
  value       = { for k, s in azapi_resource.subnet : k => s.id }
}

output "resources" {
  description = "Map of subnet name => complete azapi_resource object"
  value       = azapi_resource.subnet
}

output "lock_ids" {
  description = "Map of subnet name => management lock ID (only entries where a lock was configured)"
  value       = module.lock.ids
}

output "role_assignment_ids" {
  description = "Map of '<subnet_name>.<assignment_key>' => role assignment resource ID"
  value       = { for k, m in module.rbac : k => m.id }
}
