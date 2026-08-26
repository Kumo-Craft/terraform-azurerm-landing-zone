###############################################################
# MODULE: Vnet - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit VNet name. If null, computed from naming components."

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
  description = "Subscription acronym for naming convention (e.g. mgm, con, api)"

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
  description = "Workload name for naming convention (e.g. hub, spoke)"

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

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

###############################################################
# VNET CONFIGURATION
###############################################################
variable "address_space" {
  type        = list(string)
  description = "VNet CIDR address space (e.g. [\"10.238.0.0/22\"])"
  default     = null
  nullable    = true

  validation {
    condition     = var.address_space != null || var.ip_address_pool != null
    error_message = "Either var.address_space (manual CIDRs) or var.ip_address_pool (IPAM allocation) must be provided. Azure requires at least one address source for the VNet."
  }
}

variable "dns_servers" {
  type        = list(string)
  description = "Custom DNS server IPs. If null or empty, uses Azure default DNS."
  default     = null
  nullable    = true
}

variable "enable_ddos_protection" {
  type        = bool
  description = "Enable DDoS Standard protection on the VNet. Requires ddos_protection_plan_id."
  default     = false
}

variable "ddos_protection_plan_id" {
  type        = string
  description = "DDoS Protection Plan ID to associate with the VNet"
  default     = null
}

variable "ip_address_pool" {
  description = "Optional Azure IPAM pool configuration for the VNet"
  type = object({
    id                     = string
    number_of_ip_addresses = number
  })
  default = null
}

variable "encryption_enforcement" {
  description = "Optional VNet-level encryption enforcement (VM-to-VM confidential traffic, GA in Azure). 'AllowUnencrypted' = encrypt where possible but allow unencrypted ; 'DropUnencrypted' = require encryption (drops non-encrypted traffic). Set to null to disable VNet encryption (default Azure behavior)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.encryption_enforcement == null || contains(["AllowUnencrypted", "DropUnencrypted"], var.encryption_enforcement)
    error_message = "encryption_enforcement must be 'AllowUnencrypted' or 'DropUnencrypted' (or null to disable)."
  }
}

variable "flow_timeout_in_minutes" {
  description = "Idle flow timeout for the VNet in minutes (4-30). null = Azure default (4 minutes). Useful for hub VNets with long-lived TCP sessions (e.g. AKS, NFS)."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.flow_timeout_in_minutes == null || (var.flow_timeout_in_minutes >= 4 && var.flow_timeout_in_minutes <= 30)
    error_message = "flow_timeout_in_minutes must be between 4 and 30 (inclusive), or null to use the Azure default."
  }
}

###############################################################
# INLINE SUBNETS (optional)
###############################################################
variable "subnets" {
  description = "Optional list of subnets to create within this VNet. When empty, use the separate SubnetWithNsg module."
  type = list(object({
    name                              = string
    address_prefixes                  = optional(list(string))
    nsg_id                            = optional(string)
    service_endpoints                 = optional(list(string))
    route_table_id                    = optional(string)
    nat_gateway_id                    = optional(string)
    ip_address_pool                   = optional(object({ id = string, number_of_ip_addresses = number }))
    private_endpoint_network_policies = optional(string)
    default_outbound_access_enabled   = optional(bool, false)
    delegations = optional(list(object({
      name         = string
      service_name = string
    })), [])
  }))
  default = []

  validation {
    condition = alltrue([
      for s in var.subnets :
      s.address_prefixes == null || length(s.address_prefixes) > 0
    ])
    error_message = "address_prefixes must not be an empty list. Either omit it (null) or provide at least one CIDR block."
  }

  validation {
    condition     = length(var.subnets) == length(distinct([for s in var.subnets : s.name]))
    error_message = "Each subnet name must be unique. Duplicate names cause for_each key conflicts."
  }
}

###############################################################
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the Virtual Network scope. Common patterns: 'Network Contributor' for AKS SP, 'Reader' for Platform team. Default principal_type='ServicePrincipal' (network resources rarely user-assigned)."
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
# LOCK
###############################################################
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

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to assign to the VNet"
  default     = {}
  nullable    = false
}
