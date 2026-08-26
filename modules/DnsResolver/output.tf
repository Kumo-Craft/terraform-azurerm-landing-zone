###############################################################
# MODULE: DnsResolver - Outputs
###############################################################

output "id" {
  description = "The ID of the DNS Private Resolver"
  value       = azurerm_private_dns_resolver.this.id
}

output "name" {
  description = "The name of the DNS Private Resolver"
  value       = azurerm_private_dns_resolver.this.name
}

output "resource" {
  description = "The complete DNS Private Resolver resource object"
  value       = azurerm_private_dns_resolver.this
}

output "inbound_endpoint_ip" {
  description = "The private IP address of the inbound endpoint (use as DNS forwarder). Available after apply. For dynamic allocation (default), the IP is computed and known only post-create."
  value       = azurerm_private_dns_resolver_inbound_endpoint.this.ip_configurations[0].private_ip_address
}

output "inbound_endpoint_id" {
  description = "The ID of the inbound endpoint"
  value       = azurerm_private_dns_resolver_inbound_endpoint.this.id
}

output "outbound_endpoint_id" {
  description = "The ID of the outbound endpoint (null if not created)"
  value       = length(azurerm_private_dns_resolver_outbound_endpoint.this) > 0 ? azurerm_private_dns_resolver_outbound_endpoint.this[0].id : null
}

output "forwarding_ruleset_id" {
  description = "The ID of the DNS forwarding ruleset (null if not created)"
  value       = length(azurerm_private_dns_resolver_dns_forwarding_ruleset.this) > 0 ? azurerm_private_dns_resolver_dns_forwarding_ruleset.this[0].id : null
}

output "lock_id" {
  description = "The resource ID of the management lock (null if no lock configured)"
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment key => role assignment resource ID"
  value       = { for k, m in module.rbac : k => m.id }
}
