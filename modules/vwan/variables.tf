# ═══════════════════════════════════════════════════════════════════════════════
# VARIABLES — Virtual WAN Core
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# NAMING CONVENTION
# Convention: vwan-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    vwan-con-prod-gwc-network
# Either `name` must be set (explicit override) OR all four naming components
# must be provided to let the Naming submodule derive the WAN name.
# ───────────────────────────────────────────────────────────────────────────────

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Virtual WAN name override. If null, computed from subscription_acronym / environment / region_code / workload via the Naming submodule."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (explicit override), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym for naming convention (e.g. mgm, con, idn, sec)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment for naming convention (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code for naming convention (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name for naming convention (e.g. default, network)"

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  nullable    = false
}

variable "type" {
  description = "Type of Virtual WAN (Basic or Standard)"
  type        = string
  default     = "Standard"
  nullable    = false

  validation {
    condition     = contains(["Basic", "Standard"], var.type)
    error_message = "Type must be either 'Basic' or 'Standard'."
  }
}

variable "disable_vpn_encryption" {
  description = "Whether to disable VPN encryption for the Virtual WAN"
  type        = bool
  default     = false
}

variable "allow_branch_to_branch_traffic" {
  description = "Whether to allow branch-to-branch traffic through the Virtual WAN"
  type        = bool
  default     = true
}

variable "office365_local_breakout_category" {
  description = "Office 365 local breakout category (None, Optimize, OptimizeAndAllow, All)"
  type        = string
  default     = "None"
  nullable    = false

  validation {
    condition     = contains(["None", "Optimize", "OptimizeAndAllow", "All"], var.office365_local_breakout_category)
    error_message = "Office 365 local breakout category must be one of: None, Optimize, OptimizeAndAllow, All."
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# LOCK
# ═══════════════════════════════════════════════════════════════════════════════

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Controls the Resource Lock configuration for this resource.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TAGS
# ═══════════════════════════════════════════════════════════════════════════════

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

# ═══════════════════════════════════════════════════════════════════════════════
# RBAC COMPOSITION
# ═══════════════════════════════════════════════════════════════════════════════

variable "role_assignments" {
  description = "Map of role assignments at the Virtual WAN scope. Common patterns: 'Network Contributor' for network team granting management over the WAN. Default principal_type='ServicePrincipal' (network resources rarely user-assigned)."
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
