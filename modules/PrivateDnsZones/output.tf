output "resource_group_name" {
  description = "The name of the DNS resource group (passed through from caller)"
  value       = var.resource_group_name
}

output "private_dns_zone_resource_ids" {
  description = "Map of private DNS zone names to their resource IDs"
  value       = module.private_dns_zones.private_dns_zone_resource_ids
}
