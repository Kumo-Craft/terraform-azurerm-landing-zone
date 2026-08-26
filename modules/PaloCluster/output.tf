###############################################################
# Resource Group
###############################################################
output "resource_group_name" {
  description = "Resource group name (caller-provided passthrough)."
  value       = var.resource_group_name
}

###############################################################
# Internal Load Balancer
###############################################################
output "ilb_id" {
  description = "Internal Load Balancer ID."
  value       = azurerm_lb.trust.id
}

output "ilb_frontend_ip" {
  description = "Internal Load Balancer frontend IP."
  value       = azurerm_lb.trust.frontend_ip_configuration[0].private_ip_address
}

output "ilb_backend_pool_id" {
  description = "Internal Load Balancer backend pool ID."
  value       = azurerm_lb_backend_address_pool.trust.id
}

output "ilb_lock_ids" {
  description = "Map of ILB Resource Lock IDs (empty when no lock configured)."
  value       = module.ilb_lock.ids
}

###############################################################
# Disk Encryption
###############################################################
output "disk_encryption_set_id" {
  description = "Disk Encryption Set ID (null if no CMK)."
  value       = length(azurerm_disk_encryption_set.this) > 0 ? azurerm_disk_encryption_set.this[0].id : null
}

output "key_vault_id" {
  description = "Key Vault ID for disk encryption (null if disabled)."
  value       = length(module.kv) > 0 ? module.kv[0].id : null
}

output "des_identity_principal_id" {
  description = "DES managed identity principal ID."
  value       = length(azurerm_user_assigned_identity.des) > 0 ? azurerm_user_assigned_identity.des[0].principal_id : null
}

###############################################################
# VM-Series
###############################################################
output "vm_ids" {
  description = "Map of key => VM ID."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => v.id }
}

output "vm_names" {
  description = "Map of key => VM name."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => v.name }
}

output "mgmt_private_ips" {
  description = "Map of key => management private IP."
  value       = { for k, v in azurerm_network_interface.mgmt : k => v.private_ip_address }
}

output "trust_private_ips" {
  description = "Map of firewall key => trust NIC private IP address. Use for UDR next-hop or vwan BGP peer wiring."
  value       = { for k, v in azurerm_network_interface.trust : k => v.private_ip_address }
}

output "untrust_private_ips" {
  description = "Map of firewall key => untrust NIC private IP address. Use for external-facing UDR wiring."
  value       = { for k, v in azurerm_network_interface.untrust : k => v.private_ip_address }
}

###############################################################
# Canonical composite output — downstream composition / inspection
###############################################################
output "resources" {
  description = "Map of primary resources for downstream composition and inspection. The vm and des entries are curated field lists (not the raw resource objects) to avoid surfacing provider deprecated attributes — vm_agent_platform_updates_enabled (read-only) on the VM and managed_hsm_key_id on the DES (same pattern as FlowLogs #10939)."
  # Kept sensitive conservatively: the raw ilb object may carry provider
  # sensitive nested attributes. The curated vm map no longer embeds admin_password.
  sensitive = true
  value = {
    ilb = azurerm_lb.trust
    vm = { for k, v in azurerm_linux_virtual_machine.this : k => {
      id                 = v.id
      name               = v.name
      private_ip_address = v.private_ip_address
      virtual_machine_id = v.virtual_machine_id
      identity           = v.identity
    } }
    des = length(azurerm_disk_encryption_set.this) > 0 ? {
      id               = azurerm_disk_encryption_set.this[0].id
      name             = azurerm_disk_encryption_set.this[0].name
      identity         = azurerm_disk_encryption_set.this[0].identity
      key_vault_key_id = azurerm_disk_encryption_set.this[0].key_vault_key_id
      # OMIT managed_hsm_key_id — provider-deprecated attribute.
    } : null
  }
}

###############################################################
# Application Insights
###############################################################
output "appinsights_instrumentation_keys" {
  description = "Map of key => APPI instrumentation key (for PAN-OS config)."
  value       = { for k, v in azurerm_application_insights.this : k => v.instrumentation_key }
  sensitive   = true
}

output "appinsights_connection_strings" {
  description = "Map of key => APPI connection string."
  value       = { for k, v in azurerm_application_insights.this : k => v.connection_string }
  sensitive   = true
}
