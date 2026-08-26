###############################################################
# MODULE: PrivateDnsZonesCorp - Outputs
###############################################################

output "resource_group_name" {
  description = "Name of the resource group hosting the zones (passed through from caller)"
  value       = var.resource_group_name
}

output "zone_ids" {
  description = "Map of zone name => zone resource ID"
  value = {
    for name, zone in azurerm_private_dns_zone.this : name => zone.id
  }
}

output "zone_names" {
  description = "Set of zone names created"
  value       = [for zone in azurerm_private_dns_zone.this : zone.name]
}
