###############################################################
# MODULE: NatGateway - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit NAT Gateway name. If null, computed from naming components."

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
  description = "Subscription acronym (e.g. con, mgm)"

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
  description = "Workload name (e.g. untrust)"

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
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

variable "resource_group_id" {
  type        = string
  description = "Resource group ID (azapi parent_id)"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "resource_group_id must be a valid Azure Resource Group ID."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "idle_timeout_in_minutes" {
  type        = number
  default     = 4
  description = "Idle timeout in minutes (4-120)"

  validation {
    condition     = var.idle_timeout_in_minutes >= 4 && var.idle_timeout_in_minutes <= 120
    error_message = "idle_timeout_in_minutes must be between 4 and 120."
  }
}

variable "zones" {
  description = "Availability Zones for the NAT Gateway and base Public IP. StandardV2 SKU supports zone-redundancy with ['1','2','3']. Pass [] for no-zone (regional) deployment with no AZ constraint. Note: the original Standard SKU only supports single-zone or no-zone — this module uses StandardV2 which adds zone-redundancy."
  type        = list(string)
  default     = ["1", "2", "3"]
  nullable    = false

  validation {
    condition     = length(setsubtract(toset(var.zones), toset(["1", "2", "3"]))) == 0
    error_message = "var.zones may only contain '1', '2', or '3' (or be empty for no-zone regional deployment)."
  }
}

variable "additional_public_ips" {
  description = <<-EOT
  Optional additional public IPs to attach to the NAT Gateway. The base
  PIP (pip-<name>) is always created; entries here add pip-<name>-<key>
  alongside. Map key becomes the suffix (e.g. "02" → pip-<name>-02).
  Azure caps a NAT Gateway at 16 attached public IPs total — this map is
  capped at 15 (16 total including the base PIP).

  - `zones` - (Optional) Per-PIP zones override. Defaults to var.zones.
  EOT
  type = map(object({
    zones = optional(list(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.additional_public_ips) <= 15
    error_message = "additional_public_ips is limited to 15 entries (16 total including the base PIP — Azure NAT Gateway hard limit)."
  }
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Optional management lock on the NAT Gateway. Destroying a NAT Gateway
  breaks egress on every subnet associated with it — set kind =
  "CanNotDelete" in production to require an explicit unlock before
  teardown.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Defaults to "lock-<kind>".
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to assign"
  default     = {}
  nullable    = false
}

###############################################################
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the NAT Gateway scope. Common for granting 'Network Contributor' to policy-managed identities. Default principal_type='ServicePrincipal' (network resources rarely user-assigned)."
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

###############################################################
# PUBLIC IP PREFIX
###############################################################
variable "public_ip_prefix_ids" {
  description = "Map of existing Public IP Prefix IDs to associate with this NAT Gateway. Key is a logical name. Each prefix can be a /28-/31 block of sequential IPs (16/8/4/2 IPs respectively) — useful for BGP advertisement or firewall allow-listing where predictable CIDR is required. Composes with var.additional_public_ips (both can coexist)."
  type        = map(string)
  default     = {}
  nullable    = false
}
