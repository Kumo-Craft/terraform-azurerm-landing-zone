###############################################################
# MODULE: FlowLogs - Main
# Description: VNet Flow Logs with optional Traffic Analytics.
#              One azurerm_network_watcher_flow_log per VNet.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# network_watcher_flow_log is not a key in Azure/naming/azurerm 0.4.3,
# so we use the inline slug pattern:
#   fl-{acr}-{env}-{region}-{workload}-{vnet_key}
# The for_each guard avoids instantiation when every entry has an
# explicit name override (var.workload may then be null).
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.workload != null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  # Build per-entry name:
  #   - Use entry's explicit name when provided (F-3).
  #   - Otherwise compute from naming convention (F-1 + F-2).
  name_prefix = var.workload != null ? "fl-${join("-", module.naming["this"].suffix)}" : null

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # F-6: flatten per-entry role_assignments into a single map keyed by
  # "<vnet_key>.<assignment_key>" for use with module.rbac for_each.
  flat_role_assignments = merge([
    for vk, vv in var.vnets : {
      for rk, rv in vv.role_assignments :
      "${vk}.${rk}" => merge(rv, { vnet_key = vk })
    }
  ]...)
}

###############################################################
# RESOURCE: VNet Flow Logs
###############################################################
resource "azurerm_network_watcher_flow_log" "this" {
  for_each = var.vnets

  name                 = each.value.name != null ? each.value.name : "${local.name_prefix}-${each.key}"
  location             = var.location
  resource_group_name  = var.network_watcher_resource_group_name
  network_watcher_name = var.network_watcher_name
  target_resource_id   = each.value.id
  storage_account_id   = var.storage_account_id
  enabled              = each.value.enabled
  version              = 2

  # F-9: retention_days = 0 sends {enabled=false, days=0} to Azure.
  # Azure interprets this as "no built-in retention" — data is governed by
  # the Storage Account lifecycle management policy instead (effectively
  # infinite if no lifecycle policy is configured). It does NOT mean
  # "delete immediately". Set retention_days > 0 for an explicit cutoff.
  retention_policy {
    enabled = var.retention_days > 0
    days    = var.retention_days
  }

  dynamic "traffic_analytics" {
    for_each = var.traffic_analytics != null ? [var.traffic_analytics] : []
    content {
      enabled               = traffic_analytics.value.enabled
      workspace_id          = traffic_analytics.value.workspace_id
      workspace_region      = traffic_analytics.value.workspace_region
      workspace_resource_id = traffic_analytics.value.workspace_resource_id
      interval_in_minutes   = traffic_analytics.value.interval_minutes
    }
  }

  tags = local.common_tags
}

###############################################################
# RESOURCE: Management Locks — per-entry, delegated to ../ResourceLock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = {
    for k, v in var.vnets : k => {
      scope      = azurerm_network_watcher_flow_log.this[k].id
      lock_level = v.lock.kind
      name       = v.lock.name
    } if v.lock != null
  }
}

###############################################################
# RESOURCE: Role Assignments — per-entry, delegated to ../RoleAssignment
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = local.flat_role_assignments

  scope                            = azurerm_network_watcher_flow_log.this[each.value.vnet_key].id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
