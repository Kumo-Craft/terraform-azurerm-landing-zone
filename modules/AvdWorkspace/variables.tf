###############################################################
# MODULE: AvdWorkspace - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: vdws-{subscription_acronym}-{environment}-{region_code}-{workload}
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Explicit workspace name. If null, computed automatically."

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
  description = "Subscription acronym"

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
  description = "Workload suffix"
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

###############################################################
# WORKSPACE CONFIGURATION
###############################################################
variable "friendly_name" {
  type        = string
  description = "Display name shown in clients"
  default     = null
}

variable "description" {
  type    = string
  default = null
}

# F-2: default flipped from true → false (secure-by-default, v0.2.34 BREAKING)
# README already documented false as default — this aligns code with docs.
# Migration: callers relying on default true must pin public_network_access_enabled = true
# before upgrading if no Private Endpoint is wired. Else workspace feed access becomes
# PE-only (may break AVD client connections if Private Link not configured).
# Recommended: deploy ../PrivateEndpoint for the feed sub-resource, then use false.
variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public access to the workspace. Set false when using Private Link (feed PE)."
  default     = false
  nullable    = false
}

###############################################################
# APPLICATION GROUP ASSOCIATIONS (F-1)
###############################################################
variable "application_group_associations" {
  description = "Map of application group associations. Key = logical name (e.g. 'desktop-prod-1', 'remoteapp-finance'). Value = the application group's ID (from AvdApplicationGroup.output.id). One association resource created per map entry. AVD architecture: workspace is the user-facing client surface ; app groups are entitlements ; this map binds them."
  type        = map(string)
  default     = {}
  nullable    = false
}

###############################################################
# RESOURCE LOCK (F-3)
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the workspace. Set to null to skip."
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
# ROLE ASSIGNMENTS (F-4)
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the workspace scope. Workspace-level RBAC is less common than app-group-level (per MS Learn) but useful for AVD admin scenarios (e.g. workspace contributor grants). Default principal_type='Group'."
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
# TAGS (F-7)
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags"
}
