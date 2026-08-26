###############################################################
# Log Analytics Workspace
###############################################################
output "law_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = module.alz_management.log_analytics_workspace.id
}

output "law_name" {
  description = "The name of the Log Analytics Workspace"
  value       = module.alz_management.log_analytics_workspace.name
}

output "law_workspace_id" {
  description = "The Workspace ID (GUID) of the Log Analytics Workspace"
  value       = module.alz_management.log_analytics_workspace.workspace_id
}

###############################################################
# Automation Account
###############################################################
# No Automation Account is created (linked_automation_account_creation_enabled
# = false → CT&I via AMA, patching via Azure Update Manager). The AVM module's
# automation_account output is then null, so guard the attribute access with
# try() to return null instead of erroring at plan.
output "automation_account_id" {
  description = "The ID of the Automation Account (null — no AA is created)."
  value       = try(module.alz_management.automation_account.id, null)
}

output "automation_account_name" {
  description = "The name of the Automation Account (null — no AA is created)."
  value       = try(module.alz_management.automation_account.name, null)
}

###############################################################
# Data Collection Rules (AMA)
# Keys mirror the data_collection_rules map declared in main.tf.
# Consume these to associate the DCRs with VMs/Arc machines
# (azurerm_monitor_data_collection_rule_association) downstream.
###############################################################
output "dcr_vm_insights_id" {
  description = "Resource ID of the VM Insights Data Collection Rule."
  value       = module.alz_management.data_collection_rule_ids["vm_insights"].id
}

output "dcr_change_tracking_id" {
  description = "Resource ID of the Change Tracking & Inventory Data Collection Rule."
  value       = module.alz_management.data_collection_rule_ids["change_tracking"].id
}

output "dcr_defender_sql_id" {
  description = "Resource ID of the Defender for SQL Data Collection Rule."
  value       = module.alz_management.data_collection_rule_ids["defender_sql"].id
}

###############################################################
# Identities
###############################################################
output "ama_identity_id" {
  description = "The ID of the AMA User Assigned Identity"
  value       = module.alz_management.user_assigned_identity_ids.ama.id
}

###############################################################
# Resource Group (when created inline)
###############################################################
output "resource_group_name" {
  description = "The name of the resource group"
  value       = local.resource_group_name
}

output "resource_group_id" {
  description = "Resource Group ID. Returns the inline-created RG ID OR the caller-provided RG ID via AVM's resource_group output."
  value       = try(azurerm_resource_group.this[0].id, module.alz_management.resource_group.id)
}

###############################################################
# Resource Locks
###############################################################
output "lock_ids" {
  description = "Map of lock key => lock resource ID (keys: law, rg). Empty map when var.lock = null."
  value       = module.lock.ids
}

