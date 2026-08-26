###############################################################
# MODULE: ConsumptionBudget - Variables
###############################################################

###############################################################
# NAMING CONVENTION (mirrors sibling modules)
# Convention: bdg-{acr}-{env}-{region}-{workload}
###############################################################
variable "name" {
  description = "Explicit name override (escape hatch). If null, derived via ../Naming (bdg-{acr}-{env}-{region}-{workload})."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Either var.name must be set OR all 4 naming components (subscription_acronym, environment, region_code, workload) must be non-null."
  }
}

variable "subscription_acronym" {
  description = "Subscription acronym (e.g. mgm, con, api)."
  type        = string
  default     = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  description = "Environment code (prod / nprd)."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  description = "Region code (e.g. gwc)."
  type        = string
  default     = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  description = "Workload name (naming suffix segment)."
  type        = string
  default     = "budget"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# BUDGET
###############################################################
variable "resource_group_id" {
  description = "Full ARM ID of the resource group the budget is scoped to (/subscriptions/../resourceGroups/..)."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/.+/resourceGroups/.+$", var.resource_group_id))
    error_message = "resource_group_id must be a full resource group ARM ID."
  }
}

variable "amount" {
  description = "Budget amount in the billing account currency."
  type        = number

  validation {
    condition     = var.amount > 0
    error_message = "amount must be greater than 0."
  }
}

variable "time_grain" {
  description = "Reset period. One of: Monthly, Quarterly, Annually, BillingMonth, BillingQuarter, BillingAnnual. Immutable (ForceNew)."
  type        = string
  default     = "Monthly"

  validation {
    condition     = contains(["Monthly", "Quarterly", "Annually", "BillingMonth", "BillingQuarter", "BillingAnnual"], var.time_grain)
    error_message = "Invalid time_grain."
  }
}

variable "start_date" {
  description = "Budget start date, ISO-8601, first day of a month, UTC (e.g. 2026-07-01T00:00:00Z). Immutable once set; must be <= 12 months in the past (>= 2017-06-01)."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.start_date))
    error_message = "start_date must be the first day of a month at 00:00:00Z (YYYY-MM-01T00:00:00Z)."
  }
}

variable "end_date" {
  description = "Optional budget end date (ISO-8601). Null = provider default (~10y after start)."
  type        = string
  default     = null
  nullable    = true
}

variable "notifications" {
  description = "Threshold notifications. 1 to 5 blocks. threshold is a percentage in (0, 1000]."
  type = list(object({
    enabled        = optional(bool, true)
    threshold      = number
    operator       = optional(string, "GreaterThan") # GreaterThan | EqualTo | GreaterThanOrEqualTo
    threshold_type = optional(string, "Actual")      # Actual | Forecasted
    contact_emails = optional(list(string), [])
    contact_groups = optional(list(string), []) # Action Group resource IDs
    contact_roles  = optional(list(string), []) # RBAC role names: Owner/Contributor/Reader
  }))

  validation {
    condition     = length(var.notifications) >= 1 && length(var.notifications) <= 5
    error_message = "Provide between 1 and 5 notification blocks (Azure limit)."
  }
  validation {
    condition     = alltrue([for n in var.notifications : n.threshold > 0 && n.threshold <= 1000])
    error_message = "Each notification threshold must be within (0, 1000]."
  }
  validation {
    condition     = alltrue([for n in var.notifications : contains(["EqualTo", "GreaterThan", "GreaterThanOrEqualTo"], n.operator)])
    error_message = "notification.operator must be EqualTo, GreaterThan or GreaterThanOrEqualTo."
  }
  validation {
    condition     = alltrue([for n in var.notifications : contains(["Actual", "Forecasted"], n.threshold_type)])
    error_message = "threshold_type must be Actual or Forecasted."
  }
  validation {
    condition     = alltrue([for n in var.notifications : length(n.contact_emails) + length(n.contact_groups) + length(n.contact_roles) > 0])
    error_message = "Each notification needs at least one of contact_emails / contact_groups / contact_roles."
  }
}

variable "filter" {
  description = "Optional budget filter (restrict to dimensions/tags). Null = whole RG scope. dimension/tag operator must be 'In'."
  type = object({
    dimensions = optional(list(object({
      name     = string
      operator = optional(string, "In")
      values   = list(string)
    })), [])
    tags = optional(list(object({
      name     = string
      operator = optional(string, "In")
      values   = list(string)
    })), [])
  })
  default  = null
  nullable = true

  validation {
    condition     = var.filter == null || length(var.filter.dimensions) + length(var.filter.tags) > 0
    error_message = "When filter is set it must contain at least one dimension or tag (else leave it null)."
  }
  validation {
    condition     = var.filter == null || alltrue([for d in var.filter.dimensions : d.operator == "In"]) && alltrue([for t in var.filter.tags : t.operator == "In"])
    error_message = "filter dimension/tag operator only supports 'In'."
  }
}

###############################################################
# RESOURCE LOCK (optional) — mirrors sibling modules
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) applied to the budget. Set to null to skip."
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

variable "tags" {
  description = "Tags. NOTE: azurerm_consumption_budget_* has no tags argument (budgets don't persist tags server-side); kept for module-interface consistency, not applied to any resource."
  type        = map(string)
  default     = {}
  nullable    = false
}
