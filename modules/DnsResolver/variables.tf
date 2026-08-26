###############################################################
# MODULE: DnsResolver - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed from naming components."

  validation {
    condition = (
      var.name != null ||
      (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. con)"

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
  description = "Workload component for naming convention {type}-{acr}-{env}-{region}-{workload}."

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
  description = "Name of the pre-existing resource group in which to deploy the resolver."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be 1–90 characters and contain only letters, digits, periods, underscores, hyphens, and parentheses."
  }
}

variable "virtual_network_id" {
  type        = string
  description = "VNet ID in which to deploy the resolver"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.virtual_network_id))
    error_message = "virtual_network_id must be a valid Azure VNet resource ID."
  }
}

variable "inbound_subnet_id" {
  type        = string
  description = "Subnet ID for the inbound endpoint (Microsoft.Network/dnsResolvers delegation required)"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.inbound_subnet_id))
    error_message = "inbound_subnet_id must be a valid Azure Subnet resource ID."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "inbound_private_ip" {
  type        = string
  default     = null
  description = "Static private IP for the inbound endpoint. If null, dynamic allocation."

  validation {
    condition     = var.inbound_private_ip == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.inbound_private_ip))
    error_message = "inbound_private_ip must be a valid IPv4 address."
  }
}

variable "outbound_subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for the outbound endpoint. If null, no outbound endpoint is created."

  validation {
    condition     = var.outbound_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.outbound_subnet_id))
    error_message = "outbound_subnet_id must be a valid Azure Subnet resource ID."
  }
}

variable "forwarding_rules" {
  description = <<-EOT
  Map of DNS forwarding rules. Key = rule name.
  Requires outbound_subnet_id to be set.

  - `domain_name`        - (Required) FQDN to forward (must end with ".").
  - `target_dns_servers`  - (Required) List of target DNS servers.
  - `enabled`             - (Optional) Enable the rule. Defaults to true.
  EOT
  type = map(object({
    domain_name = string
    target_dns_servers = list(object({
      ip_address = string
      port       = optional(number, 53)
    }))
    enabled = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.forwarding_rules) == 0 || var.outbound_subnet_id != null
    error_message = "When forwarding_rules is non-empty, outbound_subnet_id must be set (outbound endpoint is required to host the forwarding ruleset)."
  }
}

variable "ruleset_vnet_links" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Map of name => VNet ID to link to the forwarding ruleset."
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
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the DNS Private Resolver scope. Default principal_type='ServicePrincipal'."
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
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}
