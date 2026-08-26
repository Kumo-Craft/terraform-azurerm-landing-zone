###############################################################
# Ipam — Azure Virtual Network Manager IPAM pools
###############################################################

variable "subscription_acronym" {
  type        = string
  nullable    = false
  description = "Subscription acronym (e.g. 'con')."
}

variable "environment" {
  type        = string
  nullable    = false
  description = "Environment (prod/nprd)."
}

variable "region_code" {
  type        = string
  nullable    = false
  description = "Region short code (e.g. 'gwc')."
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload/instance suffix for naming."
}

variable "location" {
  type        = string
  nullable    = false
  description = "Azure region for the Network Manager and its IPAM pools (ForceNew on the pools)."
}

variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Resource group hosting the Network Manager (used only when create_network_manager = true)."
}

###############################################################
# NETWORK MANAGER (AVNM) — create or bring-your-own
###############################################################
variable "create_network_manager" {
  type        = bool
  default     = true
  nullable    = false
  description = "Create a dedicated Network Manager to host the IPAM pools. Set false to attach the pools to an existing AVNM (existing_network_manager_id)."
}

variable "existing_network_manager_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Resource id of an existing Network Manager to attach the IPAM pools to. Required when create_network_manager = false."

  validation {
    condition     = var.existing_network_manager_id != null || var.create_network_manager
    error_message = "existing_network_manager_id must be set when create_network_manager = false."
  }
}

variable "network_manager_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Override for the Network Manager name. Null = derive from the Naming submodule (nm-{acr}-{env}-{region}-{workload})."
}

variable "network_manager_description" {
  type        = string
  default     = "IPAM — centralised IP address management (AVNM)."
  nullable    = true
  description = "Description of the Network Manager."
}

variable "network_manager_scope" {
  type = object({
    management_group_ids = optional(list(string), [])
    subscription_ids     = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "Scope the Network Manager manages. Provide at least one management group id or subscription id when create_network_manager = true. Management-group scope requires Microsoft.Network registered at that MG."

  validation {
    condition     = !var.create_network_manager || length(var.network_manager_scope.management_group_ids) + length(var.network_manager_scope.subscription_ids) > 0
    error_message = "network_manager_scope must contain at least one management_group_id or subscription_id when create_network_manager = true."
  }
}

variable "network_manager_scope_accesses" {
  type        = list(string)
  default     = ["Connectivity"]
  nullable    = false
  description = "Configuration deployment types allowed on the Network Manager. IPAM is available on any AVNM regardless of this list; keep it minimal. Allowed: Connectivity, SecurityAdmin, Routing."

  validation {
    condition     = length(var.network_manager_scope_accesses) > 0 && alltrue([for a in var.network_manager_scope_accesses : contains(["Connectivity", "SecurityAdmin", "Routing"], a)])
    error_message = "network_manager_scope_accesses must be a non-empty subset of [\"Connectivity\", \"SecurityAdmin\", \"Routing\"]."
  }
}

###############################################################
# IPAM POOLS (hierarchical) + STATIC CIDRs
###############################################################
variable "pools" {
  type = map(object({
    name             = optional(string) # override; null = ipam-{key}-{acr}-{env}-{region}-{workload}
    display_name     = optional(string) # portal display name; null = pool key
    description      = optional(string)
    address_prefixes = list(string)                         # CIDR(s) owned by this pool (ForceNew)
    parent_pool_key  = optional(string)                     # key of the parent pool in this same map (hierarchy)
    static_cidrs = optional(map(object({                    # carve fixed sub-CIDRs out of the pool
      name                               = optional(string) # override; null = static CIDR key
      address_prefixes                   = optional(list(string))
      number_of_ip_addresses_to_allocate = optional(string) # power-of-2 count; auto-allocated from the pool
    })), {})
  }))
  default     = {}
  nullable    = false
  description = "IPAM pools keyed by a stable local key. Reference a parent pool via parent_pool_key to build the hierarchy (root + up to 7 layers). static_cidrs reserves fixed ranges: set EITHER address_prefixes OR number_of_ip_addresses_to_allocate, not both."

  validation {
    condition     = alltrue([for k, v in var.pools : v.parent_pool_key == null || contains(keys(var.pools), v.parent_pool_key)])
    error_message = "Every pools.*.parent_pool_key must reference another key present in var.pools."
  }

  validation {
    condition     = alltrue([for k, v in var.pools : v.parent_pool_key != k])
    error_message = "A pool cannot be its own parent (pools.*.parent_pool_key must differ from its key)."
  }

  validation {
    # Two-tier hierarchy: a child's parent must be a root pool. Terraform
    # cannot order deeper self-referential chains within a single set.
    condition     = alltrue([for k, v in var.pools : v.parent_pool_key == null || try(var.pools[v.parent_pool_key].parent_pool_key, "x") == null])
    error_message = "parent_pool_key must reference a ROOT pool (one with no parent). This module supports a two-tier root -> child hierarchy."
  }

  validation {
    condition     = alltrue([for k, v in var.pools : length(v.address_prefixes) > 0])
    error_message = "Every pool must declare at least one entry in address_prefixes."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.pools : [
        for ck, cv in v.static_cidrs :
        (cv.address_prefixes != null) != (cv.number_of_ip_addresses_to_allocate != null)
      ]
    ]))
    error_message = "Each static CIDR must set EXACTLY ONE of address_prefixes or number_of_ip_addresses_to_allocate."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to the Network Manager and IPAM pools."
}
