###############################################################
# MODULE: AvdStack - Outputs
###############################################################

###############################################################
# HOST POOL
###############################################################
output "host_pool_id" {
  description = "Host pool resource ID."
  value       = module.host_pool.id
}

output "host_pool_name" {
  description = "Host pool name."
  value       = module.host_pool.name
}

output "host_pool_registration_token" {
  description = "Host pool registration token (sensitive)."
  value       = module.host_pool.registration_token
  sensitive   = true
}

###############################################################
# APPLICATION GROUPS
###############################################################
output "application_group_ids" {
  description = "Map of application group key => resource ID."
  value       = { for k, m in module.application_group : k => m.id }
}

output "application_group_names" {
  description = "Map of application group key => name."
  value       = { for k, m in module.application_group : k => m.name }
}

###############################################################
# WORKSPACE
###############################################################
output "workspace_id" {
  description = "Workspace resource ID."
  value       = module.workspace.id
}

output "workspace_name" {
  description = "Workspace name."
  value       = module.workspace.name
}

###############################################################
# SCALING PLAN (optional)
###############################################################
output "scaling_plan_id" {
  description = "Scaling plan resource ID, or null when no scaling plan was created."
  value       = one(module.scaling_plan[*].id)
}

###############################################################
# SESSION HOSTS (optional)
###############################################################
output "session_host_vm_ids" {
  description = "Map of session host VM index => VM ID, or null when no session hosts were created."
  value       = one(module.session_host[*].vm_ids)
}

output "session_host_vm_names" {
  description = "Map of session host VM index => VM name, or null when no session hosts were created."
  value       = one(module.session_host[*].vm_names)
}
