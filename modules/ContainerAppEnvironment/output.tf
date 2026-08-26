###############################################################
# MODULE: ContainerAppEnvironment - Outputs
###############################################################

output "id" {
  description = "The Container App Environment resource ID. Pass to the Container App module's container_app_environment_id."
  value       = azurerm_container_app_environment.this.id
}

output "name" {
  description = "The Container App Environment name"
  value       = azurerm_container_app_environment.this.name
}

output "default_domain" {
  description = "The default, publicly resolvable domain of the environment (apps get <app>.<default_domain>)."
  value       = azurerm_container_app_environment.this.default_domain
}

output "static_ip_address" {
  description = "The static IP of the environment (public, or internal-subnet IP when internal_load_balancer_enabled = true). Use for DNS / private DNS zone records."
  value       = azurerm_container_app_environment.this.static_ip_address
}

output "custom_domain_verification_id" {
  description = "The custom domain verification ID for binding custom domains to apps in this environment."
  value       = azurerm_container_app_environment.this.custom_domain_verification_id
}

output "identity_principal_id" {
  description = "The system-assigned identity principal ID (null when no system-assigned identity)."
  value       = try(azurerm_container_app_environment.this.identity[0].principal_id, null)
}

output "resource" {
  description = "The complete Container App Environment resource object."
  value       = azurerm_container_app_environment.this
  sensitive   = true # carries dapr_application_insights_connection_string
}
