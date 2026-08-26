###############################################################
# MODULE: NetworkStack - Outputs
###############################################################

output "resource_group_name" {
  description = "Name of the network resource group (caller-provided passthrough)."
  value       = var.resource_group_name
}

output "network_watcher_id" {
  description = "Network Watcher ID (null if create_network_watcher=false)."
  value       = var.create_network_watcher ? module.network_watcher[0].id : null
}

output "network_watcher_name" {
  description = "Network Watcher name (null if create_network_watcher=false)."
  value       = var.create_network_watcher ? module.network_watcher[0].name : null
}

output "vnet_id" {
  description = "Virtual Network ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Virtual Network name."
  value       = azurerm_virtual_network.this.name
}

output "vnet_address_space" {
  description = "Virtual Network address space(s)."
  value       = azurerm_virtual_network.this.address_space
}

output "vnet_resource" {
  description = "Full vnet resource object (for advanced consumption)."
  value       = azurerm_virtual_network.this
}

output "route_table_id" {
  description = "Route table ID (null if create_route_table=false)."
  value       = var.create_route_table ? module.route_table[0].id : null
}

output "route_table_name" {
  description = "Route table name (null if create_route_table=false)."
  value       = var.create_route_table ? module.route_table[0].name : null
}

output "subnet_ids" {
  description = "Map of subnet key => subnet resource ID."
  value       = { for k, v in azapi_resource.subnet : k => v.id }
}

output "subnet_names" {
  description = "Map of subnet key => subnet name (resolved from override or generated)."
  value       = local.subnet_names
}

output "nsg_ids" {
  description = "Map of subnet key => NSG resource ID (only entries for subnets with create_nsg=true)."
  value       = module.nsg.ids
}

output "nsg_names" {
  description = "Map of subnet key => NSG name."
  value       = module.nsg.names
}

output "hub_peering_id" {
  description = "Resource ID of the spoke->hub peering, or null when hub_peering not set."
  value       = var.hub_peering != null ? module.hub_peering.ids["hub"] : null
}
