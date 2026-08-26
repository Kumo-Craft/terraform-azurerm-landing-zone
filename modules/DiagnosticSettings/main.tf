###############################################################
# MODULE: DiagnosticSettings - Main
# Description: Creates diagnostic settings for Azure resources.
#              Supports both per-category and per-group log enabling
#              (the latter is required for AKS audit logs and any
#              resource whose categories may evolve over time).
###############################################################

locals {
  # Each enabled_log block on azurerm_monitor_diagnostic_setting accepts
  # either `category` OR `category_group` (but not both). Merge the two
  # input lists into a unified items list so a single dynamic block
  # iterates the combined set.
  log_items_per_setting = {
    for k, ds in var.diagnostic_settings : k => concat(
      [for c in ds.logs : { category = c, category_group = null }],
      [for g in ds.log_groups : { category = null, category_group = g }],
    )
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = each.value.name
  target_resource_id             = each.value.target_resource_id
  log_analytics_workspace_id     = each.value.log_analytics_workspace_id
  log_analytics_destination_type = each.value.log_analytics_destination_type
  storage_account_id             = each.value.storage_account_id
  eventhub_authorization_rule_id = each.value.event_hub_authorization_rule_id
  eventhub_name                  = each.value.event_hub_name
  partner_solution_id            = each.value.marketplace_partner_resource_id

  dynamic "enabled_log" {
    for_each = local.log_items_per_setting[each.key]
    content {
      category       = enabled_log.value.category
      category_group = enabled_log.value.category_group
    }
  }

  dynamic "enabled_metric" {
    for_each = each.value.metrics
    content {
      category = enabled_metric.value
    }
  }
}
