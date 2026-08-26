###############################################################
# MODULE: PrometheusAlertRules - Variables
###############################################################

###############################################################
# NAMING CONVENTION (I-2 option 3 — vars optional, no Naming submodule)
# Resource name = "${each.key}-${aks_cluster_name}" (semantically driven)
# Standard naming vars accepted for tracking/audit metadata consistency.
###############################################################

# I-2: escape hatch, accepted for audit/metadata parity with sibling modules.
variable "name" {
  description = "Unused override placeholder (naming vars are optional — resource names are semantically derived from rule group keys and cluster name). Kept for house-convention metadata consistency."
  type        = string
  default     = null
  nullable    = true
}

# I-2: null-tolerant (naming vars optional for this module).
variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. api, mgm)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters (or null — naming vars are optional for this module)."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters (or null — naming vars are optional for this module)."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters (or null — naming vars are optional for this module)."
  }
}

variable "workload" {
  type        = string
  default     = "aks-alerts"
  description = "Workload suffix"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the alert rule groups"
  nullable    = false
}

# I-3: optional — allows AMW-only scoping without an AKS cluster.
variable "aks_cluster_id" {
  type        = string
  default     = null
  nullable    = true
  description = "ID of the AKS cluster. Required when aks_cluster_name is set; both must be null for AMW-only scope."

  validation {
    condition     = var.aks_cluster_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerService/managedClusters/[^/]+$", var.aks_cluster_id))
    error_message = "aks_cluster_id must be a valid Azure AKS cluster resource ID."
  }
}

# I-3: must come together with aks_cluster_id (or both null).
variable "aks_cluster_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Name of the AKS cluster (used in alert rule group names and cluster_name scope). Required when aks_cluster_id is set; both must be null for AMW-only scope."

  validation {
    condition     = (var.aks_cluster_id == null && var.aks_cluster_name == null) || (var.aks_cluster_id != null && var.aks_cluster_name != null)
    error_message = "aks_cluster_id and aks_cluster_name must be provided together (or both omitted for AMW-only scope)."
  }
}

variable "monitor_workspace_id" {
  type        = string
  description = "ID of the Azure Monitor Workspace (Prometheus scope)"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Monitor/accounts/[^/]+$", var.monitor_workspace_id))
    error_message = "monitor_workspace_id must be a valid Azure Monitor Workspace resource ID."
  }
}

# I-1: consolidated list-only API (action_group_id scalar REMOVED).
variable "action_group_ids" {
  description = "List of Action Group resource IDs to wire to every alert in this rule group. At least 1 required (Azure requires actions on alert rules). Maximum 5 (Azure limit)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.action_group_ids) >= 1
    error_message = "At least one action_group_id must be provided."
  }

  validation {
    condition     = length(var.action_group_ids) <= 5
    error_message = "action_group_ids supports at most 5 entries (Azure API hard limit)."
  }

  validation {
    condition     = alltrue([for id in var.action_group_ids : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Insights/actionGroups/[^/]+$", id))])
    error_message = "Each action_group_ids entry must be a valid Azure Action Group ARM ID."
  }
}

###############################################################
# RULE GROUPS
###############################################################
variable "rule_groups" {
  type = map(object({
    interval = optional(string, "PT1M")
    enabled  = optional(bool, true)
    alerts = map(object({
      expression  = string
      for         = optional(string, "PT15M")
      severity    = optional(number, 3)
      enabled     = optional(bool, true)
      labels      = optional(map(string), {})
      annotations = optional(map(string), {})
      # M-5: per-alert alert_resolution override.
      alert_resolution = optional(object({
        auto_resolved   = optional(bool, true)
        time_to_resolve = optional(string, "PT15M")
      }), { auto_resolved = true, time_to_resolve = "PT15M" })
    }))
  }))
  description = "Map of Prometheus alert rule groups. Key = group name suffix. Max 20 rules per group (Azure limit). severity must be 0..4."
  nullable    = false

  validation {
    condition     = alltrue([for g in var.rule_groups : length(g.alerts) <= 20])
    error_message = "Each alert rule group is limited to 20 alerts (Azure hard limit on azurerm_monitor_alert_prometheus_rule_group). Split into multiple groups if you have more."
  }

  validation {
    condition = alltrue([
      for g in var.rule_groups : alltrue([
        for a in g.alerts : a.severity >= 0 && a.severity <= 4
      ])
    ])
    error_message = "Each alert severity must be in [0..4] (0=critical, 4=verbose)."
  }

  # M-8: ISO 8601 interval — Azure enforces PT1M..PT20M for Prometheus rule group interval.
  validation {
    condition = alltrue([
      for g in values(var.rule_groups) :
      can(regex("^PT([1-9]|1[0-9]|20)M$", g.interval))
    ])
    error_message = "Each rule_group.interval must be ISO 8601 between PT1M and PT20M (Azure Prometheus rule group interval limits)."
  }

  # M-8: ISO 8601 for alert.for when set.
  validation {
    condition = alltrue(flatten([
      for g in values(var.rule_groups) : [
        for a in values(g.alerts) : a.for == null || can(regex("^PT[0-9]+(M|H|S)$", a.for))
      ]
    ]))
    error_message = "Each alert.for must be ISO 8601 duration (PT<N>M|H|S) when set."
  }

  # M-8: ISO 8601 for alert_resolution.time_to_resolve when set.
  validation {
    condition = alltrue(flatten([
      for g in values(var.rule_groups) : [
        for a in values(g.alerts) : a.alert_resolution == null || can(regex("^PT[0-9]+(M|H|S)$", a.alert_resolution.time_to_resolve))
      ]
    ]))
    error_message = "Each alert_resolution.time_to_resolve must be ISO 8601 duration (PT<N>M|H|S) when set."
  }
}

###############################################################
# RESOURCE LOCK — I-4
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on each alert rule group. Applies to all groups in var.rule_groups. Set to null to skip."
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
# OPTIONAL VARIABLES
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false # M-1
  description = "Tags to apply"
}
