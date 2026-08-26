###############################################################
# MODULE: SecurityCenterWorkspace - Outputs
###############################################################

output "id" {
  description = "Resource ID of the workspaceSettings (always .../workspaceSettings/default)."
  value       = azurerm_security_center_workspace.this.id
}

output "scope" {
  description = "Subscription scope this setting applies to."
  value       = azurerm_security_center_workspace.this.scope
}

# Convenience alias for the LAW workspace ID. F-1's `output "resource"` exposes `.resource.workspace_id` as the canonical access path.
output "workspace_id" {
  description = "Log Analytics Workspace resource ID receiving Defender for Cloud data."
  value       = azurerm_security_center_workspace.this.workspace_id
}

output "resource" {
  description = "Full azurerm_security_center_workspace resource object."
  value       = azurerm_security_center_workspace.this
}
