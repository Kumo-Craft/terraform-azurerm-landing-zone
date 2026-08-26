###############################################################
# MODULE: Ampls - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name for the AMPLS. If null, computed from naming components (pls-{acr}-{env}-{region}-{workload})."

  validation {
    condition = (
      var.name != null ||
      (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either var.name must be set, OR all of subscription_acronym/environment/region_code/workload must be provided."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm). Used for computed naming when var.name is null."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd). Used for computed naming when var.name is null."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu). Used for computed naming when var.name is null."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload component (e.g. management). Used for computed naming when var.name is null."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "ingestion_access_mode" {
  type        = string
  description = "AMPLS ingestion access mode: Open or PrivateOnly"
  default     = "PrivateOnly"

  validation {
    condition     = contains(["Open", "PrivateOnly"], var.ingestion_access_mode)
    error_message = "ingestion_access_mode must be Open or PrivateOnly."
  }
}

variable "query_access_mode" {
  type        = string
  description = "AMPLS query access mode: Open or PrivateOnly"
  default     = "PrivateOnly"

  validation {
    condition     = contains(["Open", "PrivateOnly"], var.query_access_mode)
    error_message = "query_access_mode must be Open or PrivateOnly."
  }
}

variable "scoped_services" {
  description = "Map of services to link to the AMPLS (e.g. law, dce). Key = logical name."
  type = map(object({
    resource_id = string
  }))
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.scoped_services :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", v.resource_id))
    ])
    error_message = "Each scoped_service resource_id must be a valid Azure resource ID."
  }

  validation {
    condition     = length(var.scoped_services) <= 50
    error_message = "Azure Monitor Private Link Scope limit: maximum 50 scoped resources per AMPLS. Source: https://learn.microsoft.com/azure/azure-monitor/logs/private-link-configure"
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the private endpoint"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid Azure Subnet resource ID."
  }
}

variable "private_dns_zone_ids" {
  type        = list(string)
  description = "List of private DNS zone IDs for the PE DNS zone group"
  nullable    = false
}

###############################################################
# LOCK
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Controls the Resource Lock configuration for the AMPLS resource.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

###############################################################
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the AMPLS scope. Default principal_type='ServicePrincipal'."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "ServicePrincipal")
    condition                        = optional(string)
    condition_version                = optional(string)
    description                      = optional(string)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for ra in var.role_assignments :
      contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)
    ])
    error_message = "principal_type must be one of User/Group/ServicePrincipal/ForeignGroup/Device."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
  nullable    = false
}
