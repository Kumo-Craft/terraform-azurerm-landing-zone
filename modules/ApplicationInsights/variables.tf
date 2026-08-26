###############################################################
# MODULE: ApplicationInsights - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed from naming components (appi-{sub}-{env}-{region}-{workload})."

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
  description = "Workload suffix (e.g. 01, sre-01)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
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
  description = "Resource group name"
  nullable    = false
}

variable "workspace_id" {
  type        = string
  nullable    = false
  description = "REQUIRED. Resource ID of the Log Analytics workspace backing this workspace-based Application Insights (the telemetry backing store). Classic (non-workspace) App Insights is retired."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.workspace_id))
    error_message = "workspace_id must be a valid Log Analytics workspace resource ID (Microsoft.OperationalInsights/workspaces)."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "application_type" {
  type        = string
  default     = "web"
  nullable    = false
  description = "Application type. Defaults to 'web'."

  validation {
    condition     = contains(["web", "other", "java", "MobileCenter", "phone", "store", "ios", "Node.JS"], var.application_type)
    error_message = "application_type must be one of: web, other, java, MobileCenter, phone, store, ios, Node.JS."
  }
}

variable "retention_in_days" {
  type        = number
  default     = 90
  description = "Data retention in days. Note: ingestion/retention is billed through the backing Log Analytics workspace."

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.retention_in_days)
    error_message = "retention_in_days must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730."
  }
}

variable "sampling_percentage" {
  type        = number
  default     = null
  description = "Optional. Percentage of telemetry sampled (0-100). Null = provider default (100)."

  validation {
    condition     = var.sampling_percentage == null || (var.sampling_percentage >= 0 && var.sampling_percentage <= 100)
    error_message = "sampling_percentage must be between 0 and 100."
  }
}

variable "local_authentication_disabled" {
  type        = bool
  default     = null
  description = "Optional. Disable non-Entra (local/API-key) authentication. Null = provider default (false). Set true to enforce Entra-only ingestion."
}

variable "internet_ingestion_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether telemetry ingestion from the public internet is enabled. Default true: private link is enforced on the backing Log Analytics workspace itself."
}

variable "internet_query_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether querying from the public internet is enabled. Default true: private link is enforced on the backing Log Analytics workspace itself."
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the Application Insights component. Set to null to skip."
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
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the Application Insights scope. Common roles: 'Monitoring Reader', 'Monitoring Contributor'. Default principal_type='ServicePrincipal'."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "ServicePrincipal")
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
