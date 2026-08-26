###############################################################
# MODULE: ApplicationGateway - Outputs
###############################################################

output "id" {
  description = "Application Gateway ID"
  value       = azurerm_application_gateway.this.id
}

output "name" {
  description = "Application Gateway name"
  value       = azurerm_application_gateway.this.name
}

output "waf_policy_id" {
  description = "WAF Policy ID"
  value       = azurerm_web_application_firewall_policy.this.id
}

output "public_ip_address" {
  description = "Public IP address (if created)"
  value       = var.create_public_ip ? azurerm_public_ip.this[0].ip_address : null
}

output "private_ip_address" {
  description = "Private IP address of the frontend"
  value       = [for fe in azurerm_application_gateway.this.frontend_ip_configuration : fe.private_ip_address if fe.name == "frontend-private"][0]
}

output "resource" {
  description = "The complete Application Gateway resource object"
  # sensitive=true because azurerm_application_gateway embeds ssl_certificate[*].data raw PFX bytes
  # (KV-managed certs). Same pattern as TlsSelfSignedCert v0.2.64 F-4 + Vm-Windows v0.2.71 F-8 +
  # PaloCluster v0.2.74 F-10.
  sensitive = true
  value     = azurerm_application_gateway.this
}

output "role_assignment_ids" {
  description = "Map of role assignment IDs keyed by the role_assignments input map key."
  value       = { for k, m in module.rbac : k => m.id }
}
