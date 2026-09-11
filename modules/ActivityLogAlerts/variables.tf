###############################################################
# MODULE: ActivityLogAlerts - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit base name. If null, computed (ala-{sub}-{env}-{region}-{workload}); each alert is named {base}-{key}."

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
  description = "Subscription acronym (e.g. pgs, mgm)"

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
  description = "Region code (e.g. gwc, frc). NOTE: this is for NAMING only — the alert resource itself is always 'global' (see main.tf)."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload suffix (e.g. servicehealth, 01)"

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
  description = "Resource group that holds the alert resources."
}

variable "scopes" {
  type        = list(string)
  nullable    = false
  description = "Scopes the alerts watch — typically the subscription ID. Activity log events raised under these scopes are evaluated."

  validation {
    condition     = length(var.scopes) > 0
    error_message = "scopes must contain at least one resource ID."
  }

  validation {
    condition     = alltrue([for s in var.scopes : can(regex("^/subscriptions/[^/]+", s))])
    error_message = "Each scope must be an ARM resource ID under /subscriptions/..."
  }
}

variable "action_group_ids" {
  type        = list(string)
  nullable    = false
  description = "Action Group IDs notified by EVERY alert in var.alerts."

  validation {
    condition     = length(var.action_group_ids) > 0
    error_message = "action_group_ids must contain at least one Action Group ID."
  }

  validation {
    condition     = alltrue([for id in var.action_group_ids : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[Mm]icrosoft\\.[Ii]nsights/actionGroups/[^/]+$", id))])
    error_message = "Each action_group_ids entry must be a valid Action Group resource ID (Microsoft.Insights/actionGroups)."
  }
}

###############################################################
# ALERTS (map-driven)
###############################################################
variable "alerts" {
  description = <<-EOT
  Map of activity-log alerts. Key becomes the name suffix ({base}-{key}).

  Per entry:
  - `category`        - (Required) Activity log category: Administrative, ServiceHealth,
                        ResourceHealth, Alert, Autoscale, Security, Recommendation, Policy.
  - `description`     - (Optional) Alert description.
  - `enabled`         - (Optional) Default true.
  - `service_health`  - (Optional) Only with category = ServiceHealth. Filter by
                        events / locations / services (lists; empty/null = all).
                        events ∈ Incident | Maintenance | Informational |
                        ActionRequired | Security. (Values are documented, not
                        hard-validated — a typo surfaces as an ARM 400 at apply.)
  - `resource_health` - (Optional) Only with category = ResourceHealth. Filter by
                        current / previous / reason (lists). current/previous ∈
                        Available | Degraded | Unavailable | Unknown; reason ∈
                        PlatformInitiated | UserInitiated | Unknown.
  EOT
  type = map(object({
    category    = string
    description = optional(string)
    enabled     = optional(bool, true)
    service_health = optional(object({
      events    = optional(list(string))
      locations = optional(list(string))
      services  = optional(list(string))
    }))
    resource_health = optional(object({
      current  = optional(list(string))
      previous = optional(list(string))
      reason   = optional(list(string))
    }))
  }))
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.alerts) : contains(["Administrative", "ServiceHealth", "ResourceHealth", "Alert", "Autoscale", "Security", "Recommendation", "Policy"], a.category)])
    error_message = "Each alerts[*].category must be one of Administrative, ServiceHealth, ResourceHealth, Alert, Autoscale, Security, Recommendation, Policy."
  }

  validation {
    condition     = alltrue([for a in values(var.alerts) : a.service_health == null || a.category == "ServiceHealth"])
    error_message = "service_health is only valid when category = \"ServiceHealth\"."
  }

  validation {
    condition     = alltrue([for a in values(var.alerts) : a.resource_health == null || a.category == "ResourceHealth"])
    error_message = "resource_health is only valid when category = \"ResourceHealth\"."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply to every alert."
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) applied to every alert. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}
