###############################################################
# MODULE: AvdApplicationGroup - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: vdag-{subscription_acronym}-{environment}-{region_code}-{workload}
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Explicit app group name. If null, computed automatically."

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
  default     = null
  description = "Workload suffix (e.g. desktop, remoteapp)"
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type     = string
  nullable = false
}

variable "resource_group_name" {
  type     = string
  nullable = false
}

variable "host_pool_id" {
  type        = string
  description = "Host pool resource ID to bind this app group to"
  nullable    = false
}

###############################################################
# APP GROUP CONFIGURATION
###############################################################
variable "type" {
  type        = string
  description = "Application group type: Desktop or RemoteApp"
  default     = "Desktop"

  validation {
    condition     = contains(["Desktop", "RemoteApp"], var.type)
    error_message = "type must be 'Desktop' or 'RemoteApp'."
  }
}

variable "friendly_name" {
  type    = string
  default = null
}

variable "description" {
  type    = string
  default = null
}

###############################################################
# DEFAULT DESKTOP DISPLAY NAME (F-9)
###############################################################
variable "default_desktop_display_name" {
  description = "Display name for the default Desktop item shown in the AVD client. Only meaningful when var.type == \"Desktop\". Ignored otherwise."
  type        = string
  default     = null
  nullable    = true
}

###############################################################
# REMOTEAPP APPLICATIONS (F-3)
###############################################################
variable "applications" {
  description = "Map of RemoteApp applications to publish. Logical key -> app definition. Only honored when var.type == \"RemoteApp\". Each app: name (display key in AVD), path (full executable path on the session host), command_line_argument_policy (DoNotAllow/Allow/Require), optional friendly_name + description + command_line_arguments + icon_path + icon_index + show_in_portal."
  type = map(object({
    name                         = string
    path                         = string
    command_line_argument_policy = string
    friendly_name                = optional(string, null)
    description                  = optional(string, null)
    command_line_arguments       = optional(string, null)
    icon_path                    = optional(string, null)
    icon_index                   = optional(number, 0)
    show_in_portal               = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.applications) : contains(["DoNotAllow", "Allow", "Require"], a.command_line_argument_policy)])
    error_message = "Each application's command_line_argument_policy must be one of DoNotAllow, Allow, Require."
  }

  validation {
    condition     = length(var.applications) == 0 || var.type == "RemoteApp"
    error_message = "var.applications can only be set when var.type == \"RemoteApp\"."
  }
}

###############################################################
# RESOURCE LOCK (F-2)
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the application group. Set to null to skip."
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
# ROLE ASSIGNMENTS (F-1)
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the application group scope. CANONICAL AVD RBAC SCOPE: 'Desktop Virtualization User' role assigned here grants end-users access to launch desktops/RemoteApps. Default principal_type='Group' (AVD standard — AAD security groups, not individual users)."
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
