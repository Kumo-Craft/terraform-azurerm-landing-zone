###############################################################
# MODULE: FlowLogs - Outputs
###############################################################

output "ids" {
  description = "Map of VNet key to flow log resource ID"
  value       = { for k, v in azurerm_network_watcher_flow_log.this : k => v.id }
}

output "names" {
  description = "Map of VNet key to flow log resource name"
  value       = { for k, v in azurerm_network_watcher_flow_log.this : k => v.name }
}

output "lock_ids" {
  description = "Map of VNet key to management lock resource ID (only entries that have a lock configured)"
  value       = module.lock.ids
}

output "role_assignment_ids" {
  description = "Map of '<vnet_key>.<assignment_key>' to role assignment resource ID"
  value       = { for k, m in module.rbac : k => m.id }
}

output "resources" {
  description = "Map of vnet_key => curated flow log attributes. Explicit field list on purpose: exposing the raw resource object surfaced the provider-deprecated network_security_group_id attribute (legacy NSG-attached model) and emitted a 'Deprecated value used' warning even though this module uses the VNet model via target_resource_id."
  value = {
    for k, v in azurerm_network_watcher_flow_log.this : k => {
      id                   = v.id
      name                 = v.name
      location             = v.location
      resource_group_name  = v.resource_group_name
      network_watcher_name = v.network_watcher_name
      target_resource_id   = v.target_resource_id
      storage_account_id   = v.storage_account_id
      enabled              = v.enabled
      version              = v.version
      retention_policy     = v.retention_policy
      traffic_analytics    = v.traffic_analytics
      tags                 = v.tags
    }
  }
}
