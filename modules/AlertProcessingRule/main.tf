###############################################################
# MODULE: AlertProcessingRule - Main
# Description: Routes alerts firing on a subscription (or RGs /
#              resources) to one or more Action Groups, WITHOUT
#              touching the alert rules themselves
#              (azurerm_monitor_alert_processing_rule_action_group).
#
# Trigger use case: AMBA-ALZ deploys its alerts via DINE policies
# and, by design, WITHOUT an action group — routing must be done
# with an Alert Processing Rule, otherwise the alerts notify nobody.
#
# NOTE: this is the ACTION-GROUP (add) variant. The suppression
# variant (azurerm_monitor_alert_processing_rule_suppression) does
# the OPPOSITE (mutes alerts during a maintenance window) and is a
# SEPARATE module by design — merging them would risk suppressing
# alerts while intending to route them.
###############################################################

###############################################################
# Naming Convention — house prefix `apr-` + the Naming submodule's
# suffix (Azure/naming 0.4.3 has no slug for this type, so we build
# manually — same approach LogAnalyticsAlerts uses for `sqr-`).
# Convention: apr-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    apr-mgm-prod-gwc-01
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  # Single guarded local — module.naming["this"] only exists when var.name == null.
  name = var.name != null ? var.name : "apr-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: Alert Processing Rule (add action group)
###############################################################
resource "azurerm_monitor_alert_processing_rule_action_group" "this" {
  name                 = local.name
  resource_group_name  = var.resource_group_name
  scopes               = var.scopes
  add_action_group_ids = var.add_action_group_ids

  description = var.description
  enabled     = var.enabled

  dynamic "condition" {
    for_each = var.condition != null ? [var.condition] : []
    content {
      dynamic "alert_context" {
        for_each = condition.value.alert_context != null ? [condition.value.alert_context] : []
        content {
          operator = alert_context.value.operator
          values   = alert_context.value.values
        }
      }
      dynamic "alert_rule_id" {
        for_each = condition.value.alert_rule_id != null ? [condition.value.alert_rule_id] : []
        content {
          operator = alert_rule_id.value.operator
          values   = alert_rule_id.value.values
        }
      }
      dynamic "alert_rule_name" {
        for_each = condition.value.alert_rule_name != null ? [condition.value.alert_rule_name] : []
        content {
          operator = alert_rule_name.value.operator
          values   = alert_rule_name.value.values
        }
      }
      dynamic "description" {
        for_each = condition.value.description != null ? [condition.value.description] : []
        content {
          operator = description.value.operator
          values   = description.value.values
        }
      }
      dynamic "monitor_condition" {
        for_each = condition.value.monitor_condition != null ? [condition.value.monitor_condition] : []
        content {
          operator = monitor_condition.value.operator
          values   = monitor_condition.value.values
        }
      }
      dynamic "monitor_service" {
        for_each = condition.value.monitor_service != null ? [condition.value.monitor_service] : []
        content {
          operator = monitor_service.value.operator
          values   = monitor_service.value.values
        }
      }
      dynamic "severity" {
        for_each = condition.value.severity != null ? [condition.value.severity] : []
        content {
          operator = severity.value.operator
          values   = severity.value.values
        }
      }
      dynamic "signal_type" {
        for_each = condition.value.signal_type != null ? [condition.value.signal_type] : []
        content {
          operator = signal_type.value.operator
          values   = signal_type.value.values
        }
      }
      dynamic "target_resource" {
        for_each = condition.value.target_resource != null ? [condition.value.target_resource] : []
        content {
          operator = target_resource.value.operator
          values   = target_resource.value.values
        }
      }
      dynamic "target_resource_group" {
        for_each = condition.value.target_resource_group != null ? [condition.value.target_resource_group] : []
        content {
          operator = target_resource_group.value.operator
          values   = target_resource_group.value.values
        }
      }
      dynamic "target_resource_type" {
        for_each = condition.value.target_resource_type != null ? [condition.value.target_resource_type] : []
        content {
          operator = target_resource_type.value.operator
          values   = target_resource_type.value.values
        }
      }
    }
  }

  tags = var.tags
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_alert_processing_rule_action_group.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
