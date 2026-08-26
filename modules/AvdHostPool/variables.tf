###############################################################
# MODULE: AvdHostPool - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: vdpool-{subscription_acronym}-{environment}-{region_code}-{workload}
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Explicit host pool name. If null, computed automatically."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. avd, api)"

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
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload suffix (e.g. pooled, personal)"
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
  description = "Resource group name"
  nullable    = false
}

###############################################################
# HOST POOL CONFIGURATION
###############################################################
variable "type" {
  type        = string
  description = "Host pool type: Pooled or Personal"
  default     = "Pooled"
  nullable    = false

  validation {
    condition     = contains(["Pooled", "Personal"], var.type)
    error_message = "type must be 'Pooled' or 'Personal'."
  }
}

variable "load_balancer_type" {
  type        = string
  description = "Load balancer algorithm: BreadthFirst, DepthFirst, or Persistent (Personal only)"
  default     = "BreadthFirst"
  nullable    = false

  validation {
    condition     = contains(["BreadthFirst", "DepthFirst", "Persistent"], var.load_balancer_type)
    error_message = "load_balancer_type must be 'BreadthFirst', 'DepthFirst', or 'Persistent'."
  }
}

variable "maximum_sessions_allowed" {
  type        = number
  description = "Max concurrent sessions per session host (Pooled only). MS recommends 8-16 for Win11 multi-session."
  default     = 8
  nullable    = false
}

variable "preferred_app_group_type" {
  type        = string
  description = "Preferred app group type: 'Desktop' (full desktop session), 'RailApplications' (RemoteApp individual apps), or 'None' (no default app group)."
  default     = "Desktop"
  nullable    = false

  validation {
    condition     = contains(["Desktop", "RailApplications", "None"], var.preferred_app_group_type)
    error_message = "preferred_app_group_type must be 'Desktop', 'RailApplications', or 'None'."
  }
}

variable "start_vm_on_connect" {
  type        = bool
  description = "Wake session hosts from deallocated state on incoming connection (pairs with Autoscale)"
  default     = true
  nullable    = false
}

variable "validate_environment" {
  type        = bool
  description = "Mark as validation environment (receives AVD agent updates first)"
  default     = false
  nullable    = false
}

# F-1: default flipped from "Enabled" to "Disabled" (secure-by-default, v0.2.31 BREAKING)
variable "public_network_access" {
  type        = string
  description = "Controls public endpoint: 'Enabled', 'Disabled', 'EnabledForClientsOnly', 'EnabledForSessionHostsOnly'."
  default     = "Disabled"
  nullable    = false

  validation {
    condition     = contains(["Enabled", "Disabled", "EnabledForClientsOnly", "EnabledForSessionHostsOnly"], var.public_network_access)
    error_message = "public_network_access must be 'Enabled', 'Disabled', 'EnabledForClientsOnly', or 'EnabledForSessionHostsOnly'."
  }
}

###############################################################
# REGISTRATION TOKEN (for session host joining)
###############################################################
variable "create_registration_info" {
  type        = bool
  description = "If true, creates a registration token usable by session host DSC extension to register to the host pool."
  default     = false
  nullable    = false
}

variable "registration_expiration_hours" {
  type        = number
  description = "Registration token lifetime in hours (1-720). Defaults to 48h."
  default     = 48
  nullable    = false

  validation {
    condition     = var.registration_expiration_hours >= 1 && var.registration_expiration_hours <= 720
    error_message = "registration_expiration_hours must be between 1 and 720 (30 days)."
  }
}

variable "friendly_name" {
  type        = string
  description = "Display name shown in clients"
  default     = null
}

variable "description" {
  type    = string
  default = null
}

variable "custom_rdp_properties" {
  type        = string
  description = "Semicolon-separated RDP properties (e.g. \"audiocapturemode:i:1;camerastoredirect:s:*\")"
  default     = null
}

###############################################################
# PERSONAL POOL ASSIGNMENT (F-3)
###############################################################
variable "personal_desktop_assignment_type" {
  description = "Personal pool desktop assignment type — 'Automatic' (Azure auto-assigns first connecting user) or 'Direct' (manual assignment). Only relevant when var.type == \"Personal\"; ignored otherwise."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.personal_desktop_assignment_type == null || contains(["Automatic", "Direct"], coalesce(var.personal_desktop_assignment_type, "Automatic"))
    error_message = "personal_desktop_assignment_type must be 'Automatic' or 'Direct' (or null for Pooled host pools)."
  }
}

###############################################################
# SCHEDULED AGENT UPDATES (F-8)
###############################################################
variable "scheduled_agent_updates" {
  description = "Optional scheduled agent updates configuration for the host pool — pins session host agent updates to a maintenance window. Set to null to use Azure default (unmanaged)."
  type = object({
    enabled                   = optional(bool, false)
    timezone                  = optional(string)
    use_session_host_timezone = optional(bool, false)
    schedule = optional(list(object({
      day_of_week = string
      hour_of_day = number
    })), [])
  })
  default  = null
  nullable = true

  validation {
    condition     = var.scheduled_agent_updates == null || length(coalesce(var.scheduled_agent_updates != null ? var.scheduled_agent_updates.schedule : null, [])) <= 2
    error_message = "scheduled_agent_updates.schedule supports at most 2 entries (Azure API hard limit)."
  }

  validation {
    condition = var.scheduled_agent_updates == null || alltrue([
      for s in coalesce(var.scheduled_agent_updates != null ? var.scheduled_agent_updates.schedule : null, []) :
      contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], s.day_of_week)
    ])
    error_message = "Each schedule.day_of_week must be a valid weekday."
  }

  validation {
    condition = var.scheduled_agent_updates == null || alltrue([
      for s in coalesce(var.scheduled_agent_updates != null ? var.scheduled_agent_updates.schedule : null, []) :
      s.hour_of_day >= 0 && s.hour_of_day <= 23
    ])
    error_message = "Each schedule.hour_of_day must be between 0 and 23."
  }
}

###############################################################
# RESOURCE LOCK (F-4)
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly). Set to null to skip lock creation."
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
# ROLE ASSIGNMENTS (F-5)
###############################################################
variable "role_assignments" {
  description = "Map of role assignments to apply at the host pool scope. Key is a logical name. Default principal_type for AVD is 'Group' (Desktop Virtualization User role is GA-restricted to AAD users/groups)."
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
# TAGS (F-6)
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags"
}
