###############################################################
# MODULE: DdosProtection - Outputs
###############################################################

output "id" {
  description = "The ID of the DDoS Protection Plan"
  value       = azurerm_network_ddos_protection_plan.this.id
}

output "name" {
  description = "The name of the DDoS Protection Plan"
  value       = azurerm_network_ddos_protection_plan.this.name
}

output "resource" {
  description = "The complete DDoS Protection Plan resource object"
  value       = azurerm_network_ddos_protection_plan.this
}

output "role_assignment_ids" {
  description = "Map of role assignment IDs keyed by the role_assignments input map key."
  value       = { for k, m in module.rbac : k => m.id }
}
