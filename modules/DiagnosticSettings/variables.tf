###############################################################
# MODULE: DiagnosticSettings - Variables
###############################################################

variable "diagnostic_settings" {
  description = <<-EOT
  A map of Diagnostic Settings to create. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `name`                                     - (Required) Diagnostic setting name.
  - `target_resource_id`                       - (Required) Target Azure resource ID.
  - `logs`                                     - (Optional) Per-category log names (e.g. ["kube-audit", "kube-apiserver"]). Defaults to [].
  - `log_groups`                               - (Optional) Category-group names (e.g. ["allLogs", "audit"]). Required for AKS audit-log capture and for resources whose categories evolve. Defaults to [].
  - `metrics`                                  - (Optional) Metric categories to enable (typically ["AllMetrics"]). Defaults to [].
  - `log_analytics_workspace_id`               - (Optional) Log Analytics Workspace ID.
  - `log_analytics_destination_type`           - (Optional) Either "Dedicated" (resource-specific tables, RECOMMENDED for new deployments per MS Learn CAF) or "AzureDiagnostics" (legacy shared table — for backward compatibility only). Default null = provider-managed.
  - `storage_account_id`                       - (Optional) Storage Account ID for archival.
  - `event_hub_authorization_rule_id`          - (Optional) Event Hub authorization rule ID.
  - `event_hub_name`                           - (Optional) Event Hub name.
  - `marketplace_partner_resource_id`          - (Optional) Marketplace partner resource ID.
  EOT
  type = map(object({
    name                            = string
    target_resource_id              = string
    logs                            = optional(list(string), [])
    log_groups                      = optional(list(string), [])
    metrics                         = optional(list(string), [])
    log_analytics_workspace_id      = optional(string)
    log_analytics_destination_type  = optional(string) # Either 'Dedicated' (resource-specific tables, RECOMMENDED for new deployments per MS Learn CAF) or 'AzureDiagnostics' (legacy shared table — for backward compatibility only). Default null = provider-managed.
    storage_account_id              = optional(string)
    event_hub_authorization_rule_id = optional(string)
    event_hub_name                  = optional(string)
    marketplace_partner_resource_id = optional(string)
  }))
  nullable = false

  validation {
    condition = alltrue([
      for ds in var.diagnostic_settings :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", ds.target_resource_id))
    ])
    error_message = "target_resource_id must be a valid Azure resource ID."
  }

  validation {
    condition = alltrue([
      for ds in var.diagnostic_settings :
      ds.log_analytics_workspace_id != null || ds.storage_account_id != null || ds.event_hub_authorization_rule_id != null || ds.marketplace_partner_resource_id != null
    ])
    error_message = "At least one destination must be set: log_analytics_workspace_id, storage_account_id, event_hub_authorization_rule_id, or marketplace_partner_resource_id."
  }

  validation {
    condition = alltrue([
      for ds in var.diagnostic_settings :
      length(ds.logs) > 0 || length(ds.log_groups) > 0 || length(ds.metrics) > 0
    ])
    error_message = "Each diagnostic setting must enable at least one of: logs, log_groups, metrics."
  }

  validation {
    condition = alltrue([
      for ds in var.diagnostic_settings :
      ds.log_analytics_destination_type == null || contains(["Dedicated", "AzureDiagnostics"], ds.log_analytics_destination_type)
    ])
    error_message = "log_analytics_destination_type, when set, must be either \"Dedicated\" or \"AzureDiagnostics\"."
  }

  # F-1: log_groups enum guard — ARM API silently ignores unknown group names.
  validation {
    condition = alltrue([
      for ds in values(var.diagnostic_settings) :
      alltrue([for g in coalesce(ds.log_groups, []) : contains(["allLogs", "audit"], g)])
    ])
    error_message = "Each log_groups[*] must be 'allLogs' or 'audit'. Azure ARM API silently ignores other values (no logs captured)."
  }

  # F-2: log_analytics_workspace_id must be a full ARM resource ID, not a workspace GUID.
  validation {
    condition = alltrue([
      for ds in values(var.diagnostic_settings) :
      ds.log_analytics_workspace_id == null || can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", ds.log_analytics_workspace_id))
    ])
    error_message = "Each log_analytics_workspace_id must be a valid LAW ARM resource ID (not just a workspace GUID)."
  }
}
