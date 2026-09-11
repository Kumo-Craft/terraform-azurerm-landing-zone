###############################################################
# MODULE: EventGridSystemTopic - Outputs
###############################################################

output "id" {
  description = "Resource ID of the Event Grid System Topic."
  value       = azurerm_eventgrid_system_topic.this.id
}

output "name" {
  description = "Name of the Event Grid System Topic."
  value       = azurerm_eventgrid_system_topic.this.name
}

output "metric_resource_id" {
  description = "Resource ID used to query metrics for the system topic (v5-ready attribute, not the deprecated metric_arm_resource_id)."
  value       = azurerm_eventgrid_system_topic.this.metric_resource_id
}

output "event_subscription_id" {
  description = "Resource ID of the webhook event subscription."
  value       = azurerm_eventgrid_system_topic_event_subscription.this.id
}

output "event_subscription_name" {
  description = "Name of the webhook event subscription."
  value       = azurerm_eventgrid_system_topic_event_subscription.this.name
}

output "lock_ids" {
  description = "Map of lock key => lock ID (empty when var.lock is null)."
  value       = module.lock.ids
}
