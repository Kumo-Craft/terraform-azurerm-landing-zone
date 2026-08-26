###############################################################
# MODULE: ServiceBus - Outputs
###############################################################

output "id" {
  description = "The ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.this.id
}

output "name" {
  description = "The name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.this.name
}

output "endpoint" {
  description = "The Service Bus namespace endpoint URL"
  value       = azurerm_servicebus_namespace.this.endpoint
}

output "identity_principal_id" {
  description = "Principal ID of the namespace managed identity (null if no identity block)."
  value       = try(azurerm_servicebus_namespace.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "Tenant ID of the namespace managed identity (null if no identity block)."
  value       = try(azurerm_servicebus_namespace.this.identity[0].tenant_id, null)
}

output "default_primary_connection_string" {
  description = "Default (RootManageSharedAccessKey) primary connection string. Empty when local_auth_enabled = false."
  value       = azurerm_servicebus_namespace.this.default_primary_connection_string
  sensitive   = true
}

output "default_primary_key" {
  description = "Default (RootManageSharedAccessKey) primary key. Empty when local_auth_enabled = false."
  value       = azurerm_servicebus_namespace.this.default_primary_key
  sensitive   = true
}

output "queue_ids" {
  description = "Map of queue key => queue ID"
  value       = { for k, v in azurerm_servicebus_queue.this : k => v.id }
}

output "topic_ids" {
  description = "Map of topic key => topic ID"
  value       = { for k, v in azurerm_servicebus_topic.this : k => v.id }
}

output "subscription_ids" {
  description = "Map of 'topic/subscription' key => subscription ID"
  value       = { for k, v in azurerm_servicebus_subscription.this : k => v.id }
}

output "authorization_rule_ids" {
  description = "Map of namespace authorization rule name => ID"
  value       = { for k, v in azurerm_servicebus_namespace_authorization_rule.this : k => v.id }
}

output "authorization_rule_primary_connection_strings" {
  description = "Map of namespace authorization rule name => primary connection string (sensitive)."
  value       = { for k, v in azurerm_servicebus_namespace_authorization_rule.this : k => v.primary_connection_string }
  sensitive   = true
}

output "private_endpoint_ids" {
  description = "Map of private endpoint key => Private Endpoint ID"
  value       = { for k, m in module.private_endpoint : k => m.ids[k] }
}

output "private_endpoint_ips" {
  description = "Map of private endpoint key => private IP address"
  value       = { for k, m in module.private_endpoint : k => m.private_ip_addresses[k] }
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}

output "role_assignment_ids" {
  description = "Map of role assignment logical key => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
