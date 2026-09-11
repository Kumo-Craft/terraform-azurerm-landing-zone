###############################################################
# MODULE: LogAnalyticsWorkspaceTable - Variables
###############################################################

variable "workspace_id" {
  type        = string
  nullable    = false
  description = "Resource ID of the Log Analytics workspace whose tables are managed."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.workspace_id))
    error_message = "workspace_id must be a valid Log Analytics workspace resource ID (Microsoft.OperationalInsights/workspaces)."
  }
}

variable "tables" {
  description = <<-EOT
  Map of workspace tables whose plan / retention is managed. The map key is the
  exact table name (e.g. "AKSAuditAdmin", "AKSControlPlane"). Only tables that
  already exist in the workspace can be managed — resource-specific AKS* tables
  appear only once the AKS diagnostic setting is in "Dedicated" mode.

  - `plan`                    - (Optional) "Analytics" (default), "Basic" or "Auxiliary".
  - `retention_in_days`       - (Optional) Interactive retention. ONLY valid for the
                                Analytics plan (Basic/Auxiliary use a fixed interactive
                                retention). Null = workspace default.
  - `total_retention_in_days` - (Optional) Total (incl. archive/long-term) retention.
                                Valid for all plans. Null = workspace default.
  EOT
  type = map(object({
    plan                    = optional(string, "Analytics")
    retention_in_days       = optional(number, null)
    total_retention_in_days = optional(number, null)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for t in values(var.tables) : contains(["Analytics", "Basic", "Auxiliary"], t.plan)])
    error_message = "Each tables[*].plan must be one of Analytics, Basic, Auxiliary."
  }

  validation {
    # retention_in_days (interactive) is only configurable on the Analytics plan;
    # the API rejects it on Basic/Auxiliary (fixed interactive retention).
    condition     = alltrue([for t in values(var.tables) : t.retention_in_days == null || t.plan == "Analytics"])
    error_message = "retention_in_days is only valid when plan = \"Analytics\" (Basic/Auxiliary have a fixed interactive retention). Use total_retention_in_days for archive retention."
  }
}
