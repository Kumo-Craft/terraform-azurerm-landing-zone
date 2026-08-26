###############################################################
# MODULE: Vm-Windows - Outputs
###############################################################

output "vm_ids" {
  description = "Map of VM suffix => VM resource ID"
  value       = { for k, v in azurerm_windows_virtual_machine.this : k => v.id }
}

output "vm_names" {
  description = "Map of VM suffix => VM resource name"
  value       = { for k, v in azurerm_windows_virtual_machine.this : k => v.name }
}

output "computer_names" {
  description = "Map of VM suffix => Windows computer (NetBIOS hostname)"
  value       = { for k, v in azurerm_windows_virtual_machine.this : k => v.computer_name }
}

output "nic_ids" {
  description = "Map of VM suffix => NIC resource ID"
  value       = { for k, v in azurerm_network_interface.this : k => v.id }
}

output "private_ips" {
  description = "Map of VM suffix => NIC private IP"
  value       = { for k, v in azurerm_network_interface.this : k => v.private_ip_address }
}

output "principal_ids" {
  description = "Map of VM suffix => SystemAssigned identity principal ID (for RBAC grants)"
  value       = { for k, v in azurerm_windows_virtual_machine.this : k => v.identity[0].principal_id }
}

output "data_disk_ids" {
  description = "Map of '{vm_suffix}-{disk_key}' => managed disk resource ID"
  value       = { for k, v in azurerm_managed_disk.data : k => v.id }
}

# F-8: canonical plural resources map for multi-resource module.
# Marked sensitive because the VM object carries the admin_password attribute.
output "resources" {
  description = "Map of VM suffix => azurerm_windows_virtual_machine resource object. Marked sensitive because the VM object carries the admin_password attribute."
  value       = azurerm_windows_virtual_machine.this
  sensitive   = true
}

# F-6: lock IDs per VM (empty map when var.lock is null)
output "lock_ids" {
  description = "Map of VM suffix => management lock ID. Empty map when var.lock is null."
  value       = { for k, v in module.lock : k => try(v.ids["this"], null) }
}

# F-7: role assignment IDs keyed by composite key "{role_key}.{vm_key}"
output "role_assignment_ids" {
  description = "Map of composite key ({role_key}.{vm_key}) => role assignment ID. Empty map when var.role_assignments is empty."
  value       = { for k, v in module.rbac : k => v.id }
}
