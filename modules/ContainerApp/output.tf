###############################################################
# MODULE: ContainerApp - Outputs
###############################################################

output "id" {
  description = "The Container App resource ID"
  value       = azurerm_container_app.this.id
}

output "name" {
  description = "The Container App name"
  value       = azurerm_container_app.this.name
}

output "latest_revision_fqdn" {
  description = "FQDN of the latest revision of the Container App."
  value       = azurerm_container_app.this.latest_revision_fqdn
}

output "latest_revision_name" {
  description = "Name of the latest Container App revision."
  value       = azurerm_container_app.this.latest_revision_name
}

output "ingress_fqdn" {
  description = "The ingress FQDN (null when no ingress is configured)."
  value       = try(azurerm_container_app.this.ingress[0].fqdn, null)
}

output "outbound_ip_addresses" {
  description = "Public IP addresses used by the Container App for outbound access."
  value       = azurerm_container_app.this.outbound_ip_addresses
}

output "custom_domain_verification_id" {
  description = "The custom domain verification ID for binding custom domains to this app."
  value       = azurerm_container_app.this.custom_domain_verification_id
  sensitive   = true
}

output "identity_principal_id" {
  description = "The system-assigned identity principal ID (null when no system-assigned identity). Grant it AcrPull on the registry / Key Vault access."
  value       = try(azurerm_container_app.this.identity[0].principal_id, null)
}

output "resource" {
  description = "The complete Container App resource object."
  value       = azurerm_container_app.this
  sensitive   = true # carries secret values
}
