###############################################################
# Ipam - Outputs
###############################################################

output "network_manager_id" {
  description = "Resource id of the Network Manager hosting the IPAM pools (created here or the existing one passed in)."
  value       = local.network_manager_id
}

output "network_manager_name" {
  description = "Name of the Network Manager when created by this module (null when bringing your own)."
  value       = var.create_network_manager ? local.network_manager_name : null
}

output "ipam_pool_ids" {
  description = "Map of pool key => IPAM pool resource id (root and child pools merged)."
  value       = local.pool_ids
}

output "ipam_pool_names" {
  description = "Map of pool key => IPAM pool name."
  value       = local.pool_names
}

output "static_cidr_ids" {
  description = "Map of 'poolKey/cidrKey' => static CIDR resource id."
  value       = { for k, r in azurerm_network_manager_ipam_pool_static_cidr.this : k => r.id }
}
