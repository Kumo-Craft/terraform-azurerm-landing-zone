###############################################################
# MODULE: DomainServices - Outputs
###############################################################

output "id" {
  description = "The ID of the managed domain."
  value       = azurerm_active_directory_domain_service.this.id
}

output "name" {
  description = "The name of the managed domain resource."
  value       = azurerm_active_directory_domain_service.this.name
}

output "domain_name" {
  description = "The DNS domain name of the managed domain."
  value       = azurerm_active_directory_domain_service.this.domain_name
}

output "deployment_id" {
  description = "Unique ID for the managed domain deployment."
  value       = azurerm_active_directory_domain_service.this.deployment_id
}

output "initial_replica_set_id" {
  description = "ID of the initial replica set."
  value       = azurerm_active_directory_domain_service.this.initial_replica_set[0].id
}

output "domain_controller_ip_addresses" {
  description = "Domain controller IP addresses of the initial replica set (typically two). Point the VNet's custom DNS servers at these."
  value       = azurerm_active_directory_domain_service.this.initial_replica_set[0].domain_controller_ip_addresses
}

output "lock_ids" {
  description = "Map of management lock IDs (empty when var.lock is null)."
  value       = module.lock.ids
}
