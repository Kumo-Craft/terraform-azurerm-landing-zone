###############################################################
# MODULE: ManagedDevOpsPool - Outputs
###############################################################

output "id" {
  description = "The Managed DevOps Pool resource ID"
  value       = azurerm_managed_devops_pool.this.id
}

output "name" {
  description = "The Managed DevOps Pool name (use this as the pool name in Azure DevOps pipelines)"
  value       = azurerm_managed_devops_pool.this.name
}

output "dev_center_project_id" {
  description = "The Dev Center Project ID the pool is organized under"
  value       = azurerm_managed_devops_pool.this.dev_center_project_id
}

output "resource" {
  description = "The complete Managed DevOps Pool resource object"
  value       = azurerm_managed_devops_pool.this
}
