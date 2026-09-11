###############################################################
# MODULE: AlertProcessingRule - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed (apr-{sub}-{env}-{region}-{workload})."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm, con)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, frc)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload suffix (e.g. 01)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Resource group that HOLDS the Alert Processing Rule resource (not where alerts fire — see var.scopes)."
}

variable "scopes" {
  type        = list(string)
  nullable    = false
  description = <<-EOT
  Resource IDs the rule applies to — i.e. the resources on which the alerts
  FIRE (typically the whole subscription ID, but can be resource groups or
  individual resources). This is NOT where the alert rules live. All scopes
  must be within a SINGLE subscription: an APR cannot cross subscription
  boundaries (Azure Monitor service constraint).
  EOT

  validation {
    condition     = length(var.scopes) > 0
    error_message = "scopes must contain at least one resource ID."
  }

  validation {
    condition     = alltrue([for s in var.scopes : can(regex("^/subscriptions/[^/]+", s))])
    error_message = "Each scope must be an ARM resource ID under /subscriptions/... (subscription, resource group, or resource)."
  }

  # An Alert Processing Rule cannot span subscriptions — all scopes must resolve
  # to the same subscription id (Azure Monitor service constraint).
  validation {
    condition     = length(distinct([for s in var.scopes : lower(regex("^/subscriptions/([^/]+)", s)[0])])) <= 1
    error_message = "All scopes must belong to the SAME subscription — an Alert Processing Rule cannot cross subscription boundaries."
  }
}

variable "add_action_group_ids" {
  type        = list(string)
  nullable    = false
  description = "Action Group resource IDs to add to matching alerts. This is how AMBA-ALZ (policy-deployed alerts with no action group) get routed to notifications."

  validation {
    condition     = length(var.add_action_group_ids) > 0
    error_message = "add_action_group_ids must contain at least one Action Group ID."
  }

  validation {
    condition     = alltrue([for id in var.add_action_group_ids : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[Mm]icrosoft\\.[Ii]nsights/actionGroups/[^/]+$", id))])
    error_message = "Each add_action_group_ids entry must be a valid Action Group resource ID (Microsoft.Insights/actionGroups)."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "description" {
  type        = string
  default     = null
  description = "Optional description of the rule."
}

variable "enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether the rule is enabled."
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}

###############################################################
# CONDITION (optional filters)
# Each filter is { operator, values }. operator is one of
# Equals / NotEquals / Contains / DoesNotContain. Left null =
# the rule matches ALL alerts on the scopes (route everything).
# Provided as the volume lever (e.g. only Sev0/Sev1, only a
# monitor_service, a target_resource_group, ...).
###############################################################
variable "condition" {
  description = "Optional condition filters. Null = match all alerts on the scopes."
  type = object({
    alert_context         = optional(object({ operator = string, values = list(string) }))
    alert_rule_id         = optional(object({ operator = string, values = list(string) }))
    alert_rule_name       = optional(object({ operator = string, values = list(string) }))
    description           = optional(object({ operator = string, values = list(string) }))
    monitor_condition     = optional(object({ operator = string, values = list(string) }))
    monitor_service       = optional(object({ operator = string, values = list(string) }))
    severity              = optional(object({ operator = string, values = list(string) }))
    signal_type           = optional(object({ operator = string, values = list(string) }))
    target_resource       = optional(object({ operator = string, values = list(string) }))
    target_resource_group = optional(object({ operator = string, values = list(string) }))
    target_resource_type  = optional(object({ operator = string, values = list(string) }))
  })
  default = null

  # Fields that accept all 4 operators (per azurerm registry doc 13498485).
  validation {
    condition = var.condition == null || alltrue([
      for sc in [
        var.condition.alert_context, var.condition.alert_rule_id, var.condition.alert_rule_name,
        var.condition.description, var.condition.target_resource,
        var.condition.target_resource_group, var.condition.target_resource_type,
      ] : sc == null || contains(["Equals", "NotEquals", "Contains", "DoesNotContain"], sc.operator)
    ])
    error_message = "operator for alert_context / alert_rule_id / alert_rule_name / description / target_resource / target_resource_group / target_resource_type must be one of Equals, NotEquals, Contains, DoesNotContain."
  }

  # Fields the ARM API restricts to Equals / NotEquals only (the provider schema
  # is a plain string with no enum, so this would otherwise fail only at apply).
  validation {
    condition = var.condition == null || alltrue([
      for sc in [
        var.condition.monitor_condition, var.condition.monitor_service,
        var.condition.severity, var.condition.signal_type,
      ] : sc == null || contains(["Equals", "NotEquals"], sc.operator)
    ])
    error_message = "operator for monitor_condition / monitor_service / severity / signal_type must be Equals or NotEquals (ARM API restriction)."
  }

  # At least one sub-block must be set when a condition is provided — an empty
  # condition {} block is rejected by the ARM API at apply time.
  validation {
    condition = var.condition == null || anytrue([
      for sc in [
        var.condition.alert_context, var.condition.alert_rule_id, var.condition.alert_rule_name,
        var.condition.description, var.condition.monitor_condition, var.condition.monitor_service,
        var.condition.severity, var.condition.signal_type, var.condition.target_resource,
        var.condition.target_resource_group, var.condition.target_resource_type,
      ] : sc != null
    ])
    error_message = "condition, when set, must specify at least one filter sub-block."
  }
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the rule. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    # try(...,"") fails CLOSED: lock = { kind = null } is rejected here rather
    # than silently passing and failing later inside ../ResourceLock.
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}
