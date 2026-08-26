###############################################################
# MODULE: SecurityCenterWorkspace - Variables
# Configures the per-subscription default Log Analytics workspace
# used by Microsoft Defender for Cloud security operators (Defender
# for Containers, Servers, Storage, Key Vault, SQL, etc.).
#
# Without this setting, Defender auto-creates a per-region
# `DefaultResourceGroup-<region>` + `DefaultWorkspace-<subId>-<region>`
# the first time any of its security operators (e.g. the
# `DefenderForContainersSecurityOperator` managed identity) writes
# telemetry. Setting this resource redirects all Defender telemetry
# for the subscription to a central LAW (per ALZ pattern, our
# `law-mgm-{env}-gwc-01` in the management sub).
###############################################################

variable "subscription_id" {
  type        = string
  description = "Subscription where the Defender for Cloud default workspace setting applies. Accepts either a bare GUID or the full /subscriptions/<guid> path."
  nullable    = false

  validation {
    condition     = can(regex("^(/subscriptions/)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID or /subscriptions/<guid>."
  }
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Full Azure resource ID of the Log Analytics Workspace receiving Defender for Cloud data (e.g. the central law-mgm-{env}-gwc-01)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid LAW resource ID (/subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/...)."
  }
}
