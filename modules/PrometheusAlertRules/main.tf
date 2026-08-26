###############################################################
# MODULE: PrometheusAlertRules - Main
# Description: Prometheus alert rule groups for AKS clusters
#              or AMW-only scope, backed by Azure Monitor Workspace.
#              Supports multiple groups (Azure limit: 20 rules/group).
###############################################################

resource "time_static" "time" {}

###############################################################
# RESOURCE: Prometheus Alert Rule Groups
###############################################################
resource "azurerm_monitor_alert_prometheus_rule_group" "this" {
  for_each = var.rule_groups

  # I-2: resource name is semantically driven by group key + cluster name.
  # When AMW-only (aks_cluster_name = null), simplify to just the group key.
  name                = var.aks_cluster_name != null ? "${each.key}-${var.aks_cluster_name}" : each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  # I-3: cluster_name is null for AMW-only scope (attribute is optional in schema).
  cluster_name = var.aks_cluster_name
  # I-3: compact removes nulls — AMW-only path passes only monitor_workspace_id.
  scopes             = compact([var.monitor_workspace_id, var.aks_cluster_id])
  interval           = each.value.interval
  rule_group_enabled = each.value.enabled

  dynamic "rule" {
    for_each = each.value.alerts
    content {
      alert       = rule.key
      expression  = rule.value.expression
      for         = rule.value.for
      severity    = rule.value.severity
      enabled     = rule.value.enabled
      labels      = rule.value.labels
      annotations = rule.value.annotations

      dynamic "action" {
        # I-1: action_group_ids is now the single source of truth (no scalar var.action_group_id).
        for_each = var.action_group_ids
        content {
          action_group_id = action.value
        }
      }

      # M-5: per-alert alert_resolution (defaults: auto_resolved=true, time_to_resolve="PT15M").
      alert_resolution {
        auto_resolved   = rule.value.alert_resolution.auto_resolved
        time_to_resolve = rule.value.alert_resolution.time_to_resolve
      }
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Management Lock (optional) — I-4
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    for k, _ in var.rule_groups : k => {
      scope      = azurerm_monitor_alert_prometheus_rule_group.this[k].id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-${k}" : null
    }
  } : {}
}
