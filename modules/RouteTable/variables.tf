###############################################################
# MODULE: RouteTable - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Route Table name. If null, computed from naming components."

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
  description = "Workload name for naming convention (e.g. default, spoke)"

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
  description = "Azure region where the route table will be deployed"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name where the route table will be created"
  nullable    = false
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "bgp_route_propagation_enabled" {
  type        = bool
  default     = true
  description = "Whether BGP route propagation is enabled. Set to false for spoke VNets in hub-and-spoke topologies."
}

variable "routes" {
  description = <<-EOT
  A map of routes to add to the route table. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `name`                   - (Required) The name of the route.
  - `address_prefix`         - (Required) Destination CIDR or Azure Service Tag.
  - `next_hop_type`          - (Required) VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance, or None.
  - `next_hop_in_ip_address` - (Optional) Next hop IP. Required when next_hop_type is VirtualAppliance.
  EOT
  type = map(object({
    name                   = string
    address_prefix         = string
    next_hop_type          = string
    next_hop_in_ip_address = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for r in var.routes : contains(
        ["VirtualNetworkGateway", "VnetLocal", "Internet", "VirtualAppliance", "None"],
        r.next_hop_type
      )
    ])
    error_message = "next_hop_type must be one of: VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance, or None."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      r.next_hop_type != "VirtualAppliance" || r.next_hop_in_ip_address != null
    ])
    error_message = "next_hop_in_ip_address is required when next_hop_type is VirtualAppliance."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      r.next_hop_type == "VirtualAppliance" || r.next_hop_in_ip_address == null
    ])
    error_message = "next_hop_in_ip_address must be null when next_hop_type is not VirtualAppliance."
  }

  validation {
    condition     = length([for r in var.routes : r.name]) == length(distinct([for r in var.routes : r.name]))
    error_message = "Each route name must be unique within the route table."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$", r.address_prefix)) ||
      can(regex("^[A-Z][A-Za-z0-9]+(\\.[A-Z][A-Za-z0-9]+)*$", r.address_prefix))
    ])
    error_message = "Each route address_prefix must be either an IPv4 CIDR (e.g. 10.0.0.0/24) or an Azure service tag (e.g. Internet, VirtualNetwork, Storage.GermanyWestCentral)."
  }
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Controls the Resource Lock configuration for this resource.

  - `kind` - (Required) The type of lock. Possible values are "CanNotDelete" and "ReadOnly".
  - `name` - (Optional) The name of the lock. If not specified, generated from the kind value.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to assign to the route table"
  default     = {}
}
