###############################################################
# MODULE: AvdScalingPlan - Variables
# Naming: vdscaling-{sub_acronym}-{environment}-{region_code}-{workload}
###############################################################

variable "name" {
  type        = string
  default     = null
  description = "Explicit scaling plan name. If null, computed automatically."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type    = string
  default = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type    = string
  default = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type    = string
  default = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload suffix (e.g. pooled)."
  default     = "pooled"
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type        = string
  description = "Must match the host pool region."
  nullable    = false
}

variable "resource_group_name" {
  type     = string
  nullable = false
}

# F-9: corrected description — Azure AVD accepts Windows TZ names only.
variable "time_zone" {
  type        = string
  description = "Windows time zone name (e.g. 'W. Europe Standard Time', 'Romance Standard Time'). IANA names are not accepted by the Azure API."
  default     = "W. Europe Standard Time"
}

variable "friendly_name" {
  type    = string
  default = null
}

variable "description" {
  type    = string
  default = null
}

variable "exclusion_tag" {
  type        = string
  description = "Tag name on session hosts to exclude from autoscale (e.g. 'excludeFromScaling')."
  default     = null
}

###############################################################
# SCHEDULES
###############################################################
variable "schedules" {
  description = <<-EOT
  Map of scaling plan schedules. For Pooled host pools:

  - `days_of_week`                         - (Required) Set: Monday..Sunday
  - `ramp_up_start_time`                   - (Required) "HH:MM"
  - `ramp_up_load_balancing_algorithm`     - (Required) BreadthFirst | DepthFirst
  - `ramp_up_minimum_hosts_percent`        - (Optional) 0-100  (Azure default applies when omitted)
  - `ramp_up_capacity_threshold_percent`   - (Optional) 1-100  (Azure default applies when omitted)
  - `peak_start_time`                      - (Required) "HH:MM"
  - `peak_load_balancing_algorithm`        - (Required) BreadthFirst | DepthFirst
  - `ramp_down_start_time`                 - (Required) "HH:MM"
  - `ramp_down_load_balancing_algorithm`   - (Required) BreadthFirst | DepthFirst
  - `ramp_down_minimum_hosts_percent`      - (Required) 0-100
  - `ramp_down_capacity_threshold_percent` - (Required) 1-100
  - `ramp_down_force_logoff_users`         - (Required) bool
  - `ramp_down_wait_time_minutes`          - (Required) minutes before forced logoff
  - `ramp_down_notification_message`       - (Required) shown to users before logoff
  - `ramp_down_stop_hosts_when`            - (Required) ZeroActiveSessions | ZeroSessions
  - `off_peak_start_time`                  - (Required) "HH:MM"
  - `off_peak_load_balancing_algorithm`    - (Required) BreadthFirst | DepthFirst
  EOT
  # F-8: days_of_week changed list(string) → set(string) (matches provider schema).
  # F-10: ramp_up_minimum_hosts_percent + ramp_up_capacity_threshold_percent wrapped in
  #        optional() — provider schema marks both optional; Azure defaults apply when null.
  type = map(object({
    days_of_week                         = set(string)
    ramp_up_start_time                   = string
    ramp_up_load_balancing_algorithm     = string
    ramp_up_minimum_hosts_percent        = optional(number)
    ramp_up_capacity_threshold_percent   = optional(number)
    peak_start_time                      = string
    peak_load_balancing_algorithm        = string
    ramp_down_start_time                 = string
    ramp_down_load_balancing_algorithm   = string
    ramp_down_minimum_hosts_percent      = number
    ramp_down_capacity_threshold_percent = number
    ramp_down_force_logoff_users         = bool
    ramp_down_wait_time_minutes          = number
    ramp_down_notification_message       = string
    ramp_down_stop_hosts_when            = string
    off_peak_start_time                  = string
    off_peak_load_balancing_algorithm    = string
  }))
  nullable = false

  # F-11: min-1-schedule guard (provider enforces min_items: 1 at apply; catch it at plan).
  validation {
    condition     = length(var.schedules) >= 1
    error_message = "At least one schedule must be provided (Azure API min_items: 1 on schedule block)."
  }

  validation {
    condition = alltrue([
      for s in values(var.schedules) : alltrue([
        for d in tolist(s.days_of_week) :
        contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], d)
      ])
    ])
    error_message = "days_of_week entries must be PascalCase (Monday, Tuesday, … Sunday). Azure rejects lowercase or abbreviated forms."
  }

  validation {
    condition = alltrue([
      for s in values(var.schedules) :
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", s.ramp_up_start_time)) &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", s.peak_start_time)) &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", s.ramp_down_start_time)) &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", s.off_peak_start_time))
    ])
    error_message = "ramp_up_start_time, peak_start_time, ramp_down_start_time, off_peak_start_time must be HH:MM (00:00-23:59)."
  }

  # F-10: null-guard added for ramp_up_*_percent (now optional).
  validation {
    condition = alltrue([
      for s in values(var.schedules) :
      (s.ramp_up_minimum_hosts_percent == null || (s.ramp_up_minimum_hosts_percent >= 0 && s.ramp_up_minimum_hosts_percent <= 100))
      && (s.ramp_up_capacity_threshold_percent == null || (s.ramp_up_capacity_threshold_percent >= 1 && s.ramp_up_capacity_threshold_percent <= 100))
      && s.ramp_down_minimum_hosts_percent >= 0 && s.ramp_down_minimum_hosts_percent <= 100
      && s.ramp_down_capacity_threshold_percent >= 1 && s.ramp_down_capacity_threshold_percent <= 100
    ])
    error_message = "Percent fields out of range — minimum_hosts_percent must be 0-100; capacity_threshold_percent must be 1-100."
  }

  validation {
    condition = alltrue([
      for s in values(var.schedules) :
      contains(["BreadthFirst", "DepthFirst"], s.ramp_up_load_balancing_algorithm) &&
      contains(["BreadthFirst", "DepthFirst"], s.peak_load_balancing_algorithm) &&
      contains(["BreadthFirst", "DepthFirst"], s.ramp_down_load_balancing_algorithm) &&
      contains(["BreadthFirst", "DepthFirst"], s.off_peak_load_balancing_algorithm)
    ])
    error_message = "load_balancing_algorithm fields must be either BreadthFirst or DepthFirst (PascalCase)."
  }

  validation {
    condition = alltrue([
      for s in values(var.schedules) :
      contains(["ZeroActiveSessions", "ZeroSessions"], s.ramp_down_stop_hosts_when)
    ])
    error_message = "ramp_down_stop_hosts_when must be either ZeroActiveSessions or ZeroSessions (PascalCase)."
  }
}

###############################################################
# HOST POOL ASSOCIATIONS
###############################################################
variable "host_pool_associations" {
  description = "Map key => { hostpool_id, scaling_plan_enabled }"
  type = map(object({
    hostpool_id          = string
    scaling_plan_enabled = optional(bool, true)
  }))
  nullable = false
}

###############################################################
# RESOURCE LOCK (F-2)
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the scaling plan. Set to null to skip."
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
# ROLE ASSIGNMENTS (F-3)
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the scaling plan scope. Useful for AVD admin contributor visibility scenarios. Default principal_type='Group'."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "Group")
    condition                        = optional(string, null)
    condition_version                = optional(string, null)
    description                      = optional(string, null)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}

###############################################################
# TAGS
###############################################################
# F-7: nullable = false added (merge(null, ...) would panic).
variable "tags" {
  type     = map(string)
  default  = {}
  nullable = false
}
