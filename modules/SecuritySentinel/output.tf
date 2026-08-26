output "law_id" {
  value       = module.law.id
  description = "Resource id of the Sentinel Log Analytics Workspace (for AMPLS scoped service)."
}

output "law_name" {
  value       = module.law.name
  description = "Name of the Sentinel LAW."
}

output "law_workspace_id" {
  value       = module.law.workspace_id
  description = "Workspace (customer) id — GUID."
}

output "resource_group_name" {
  value       = var.resource_group_name
  description = "RG hosting the Sentinel LAW."
}
