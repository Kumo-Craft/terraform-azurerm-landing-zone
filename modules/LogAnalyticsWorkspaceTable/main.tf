###############################################################
# MODULE: LogAnalyticsWorkspaceTable - Main
# Description: Manages the plan / retention of EXISTING tables in a
#              Log Analytics workspace (azurerm_log_analytics_workspace_table).
#
# Scope note: LogAnalyticsWorkspace deliberately excludes table-level
# plan/retention ("Out of scope (compose separately): table-level RBAC /
# retention"). This module fills that gap without contradicting it —
# compose it alongside LogAnalyticsWorkspace.
#
# Primary use case (cost): put high-volume AKS control-plane tables on the
# Basic plan (~0.65 $/GB vs ~2.99 $/GB), per MS Learn
# (learn.microsoft.com/azure/aks/monitor-aks#azure-monitor-resource-logs).
###############################################################

resource "azurerm_log_analytics_workspace_table" "this" {
  for_each = var.tables

  workspace_id            = var.workspace_id
  name                    = each.key
  plan                    = each.value.plan
  retention_in_days       = each.value.retention_in_days
  total_retention_in_days = each.value.total_retention_in_days
}
