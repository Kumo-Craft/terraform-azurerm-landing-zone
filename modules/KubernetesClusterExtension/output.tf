###############################################################
# MODULE: KubernetesClusterExtension - Outputs
###############################################################

output "id" {
  description = "Resource ID of the cluster extension."
  value       = azurerm_kubernetes_cluster_extension.this.id
}

output "name" {
  description = "Extension name on the cluster."
  value       = azurerm_kubernetes_cluster_extension.this.name
}

output "current_version" {
  description = "Currently installed extension version (read after apply)."
  value       = azurerm_kubernetes_cluster_extension.this.current_version
}

# F-1: Canonical resource output. azurerm_kubernetes_cluster_extension has no sensitive
# computed attributes (Truth 6 N/A, confirmed via azurerm 4.75.0 schema). However,
# sensitive=true is required here because var.configuration_protected_settings (sensitive=true
# on the variable) propagates into the resource object, which Terraform rejects unless the
# output is explicitly marked sensitive.
output "resource" {
  description = "The azurerm_kubernetes_cluster_extension resource."
  value       = azurerm_kubernetes_cluster_extension.this
  sensitive   = true
}

# F-2: Extension MSI identity output.
output "aks_assigned_identity" {
  description = "Extension's system-assigned managed identity (principal_id, tenant_id, type). Empty list if no identity assigned by Azure (depends on extension type)."
  value       = azurerm_kubernetes_cluster_extension.this.aks_assigned_identity
}

# F-7: ResourceLock composition output.
output "lock_id" {
  description = "Resource lock ID when var.lock is set, otherwise null."
  value       = try(module.lock.ids["this"], null)
}

# F-3: RoleAssignment composition output.
output "role_assignment_ids" {
  description = "Map of role assignment IDs keyed by the var.role_assignments map key."
  value       = { for k, v in module.role_assignments : k => v.id }
}
