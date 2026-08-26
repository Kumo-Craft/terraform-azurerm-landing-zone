###############################################################
# MODULE: ContainerInsightsCollector - Variables
#
# Deploys an explicit DCR + DCRA pair that route Container Insights
# streams (ContainerLogV2, KubeEvents, KubePodInventory, etc.) from
# an AKS cluster to a Log Analytics Workspace. Companion to the
# `oms_agent` addon enabled on the cluster — the addon installs the
# ama-logs DaemonSet, this DCR tells it where + what to ship.
#
# Modern MS-recommended pattern (kubernetes-monitoring-enable.md,
# Terraform tab, updated 2026-04-17): the addon auto-creates a default
# DCR, but callers typically deploy this explicit one to:
#   - opt into ContainerLogV2 only (drop deprecated ContainerLog V1)
#   - skip Microsoft-Perf (redundant with Managed Prometheus)
#   - apply namespace filtering / data collection settings
#   - control stream selection precisely
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################

# F-1: var.name override (escape hatch) + XOR validator.
variable "name" {
  description = "Explicit DCR name override (escape hatch). If null, derived from naming convention via ../Naming."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null)
    error_message = "Either var.name must be set OR all 3 naming components (subscription_acronym, environment, region_code) must be non-null. workload has a default."
  }
}

# F-1: default = null + null-tolerant validators.
variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. shc, api, mgm)."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters (or null when var.name is set)."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters (or null when var.name is set)."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters (or null when var.name is set)."
  }
}

variable "workload" {
  type        = string
  default     = "containerinsights"
  nullable    = false
  description = "Workload suffix in the DCR/DCRA names."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type        = string
  description = "Azure region for the DCR (must match the AKS cluster's region)."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group where the DCR is deployed (typically the AKS cluster RG)."
  nullable    = false
}

variable "aks_cluster_id" {
  type        = string
  description = "Full resource ID of the AKS cluster to associate the DCR with."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerService/managedClusters/[^/]+$", var.aks_cluster_id))
    error_message = "aks_cluster_id must be a valid AKS resource ID."
  }
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Full resource ID of the Log Analytics Workspace receiving Container Insights data."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid LAW resource ID."
  }
}

###############################################################
# OPTIONAL
###############################################################
# F-8: nullable = false added.
variable "streams" {
  type        = list(string)
  nullable    = false
  description = <<-EOT
  Streams to collect. Defaults to the modern Container Insights set
  (ContainerLogV2 for stdout/stderr, KubeEvents, KubePodInventory,
  KubeNodeInventory, KubeServices, KubePVInventory, KubeMonAgentEvents,
  ContainerNodeInventory, ContainerInventory, InsightsMetrics).

  Skipped on purpose vs the addon defaults:
    - Microsoft-ContainerLog (V1, deprecated — use V2)
    - Microsoft-Perf (redundant with Managed Prometheus)
  EOT
  default = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
    "Microsoft-KubeNodeInventory",
    "Microsoft-KubeServices",
    "Microsoft-KubePVInventory",
    "Microsoft-KubeMonAgentEvents",
    "Microsoft-ContainerNodeInventory",
    "Microsoft-ContainerInventory",
    "Microsoft-InsightsMetrics",
  ]
}

# F-7: nullable = false added.
variable "data_collection_settings" {
  type = object({
    interval                = optional(string, "1m")
    namespace_filter_mode   = optional(string, "Off")
    namespaces              = optional(list(string), [])
    enable_container_log_v2 = optional(bool, true)
  })
  nullable    = false
  description = <<-EOT
  Container Insights agent settings (passed as extension_json to the
  ContainerInsights data source extension).

  - interval: scrape interval, ISO 8601-ish (e.g. "1m", "30s").
  - namespace_filter_mode: "Off" (collect all), "Include", or "Exclude".
  - namespaces: list of k8s namespaces matching the filter mode.
  - enable_container_log_v2: emit ContainerLogV2 (modern) when true.
  EOT
  default     = {}
}

# F-6: nullable = false added.
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to the DCR."
}

###############################################################
# RESOURCE LOCK
###############################################################

# F-3: ResourceLock composition variable.
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the DCR. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock != null ? var.lock.kind : null, "CanNotDelete"))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}

###############################################################
# ROLE ASSIGNMENTS
###############################################################

# F-4: RoleAssignment composition variable.
variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this DCR. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition.
  - `principal_id`                           - (Required) The ID of the principal to assign the role to.
  - `principal_type`                         - (Optional) User, Group, or ServicePrincipal.
  - `condition`                              - (Optional) ABAC condition.
  - `condition_version`                      - (Optional) Condition version ("2.0").
  - `description`                            - (Optional) Description.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check.
  - `delegated_managed_identity_resource_id` - (Optional) Cross-tenant.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    principal_type                         = optional(string, "ServicePrincipal")
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string, null)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}
