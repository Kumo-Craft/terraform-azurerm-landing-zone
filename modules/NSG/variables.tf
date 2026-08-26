###############################################################
# MODULE: NSG - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "subscription_acronym" {
  type        = string
  description = "Subscription acronym (e.g. con, api, mgm)"

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = <<-EOT
  Workload segment of the house naming convention. Present for symmetry
  with other modules and Terragrunt `include.root.inputs.workload` wiring,
  but **intentionally NOT used in the NSG name** — this module is
  map-shaped (`var.nsgs`) and uses each map key as the per-NSG workload
  segment (final name: `nsg-{acr}-{env}-{region}-{key}`). Callers can
  pass this variable safely; it is forwarded to the Naming submodule but
  the produced names rely on the map key, not on this value.

  Provided so Terragrunt configs don't need a NSG-specific override of
  the standard `inputs.workload` pattern.
  EOT
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
  description = "Resource group where NSGs are created"
  nullable    = false
}

###############################################################
# NSG DEFINITIONS
###############################################################
variable "nsgs" {
  description = <<-EOT
  Map of NSGs to create. Key = workload suffix (used in naming: nsg-{sub}-{env}-{region}-{key}).
  Value = list of security rules for that NSG.

  Each security rule supports:
  - `name`                  - (Required) Rule name.
  - `priority`              - (Required) Priority between 100 and 4096.
  - `direction`             - (Required) "Inbound" or "Outbound".
  - `access`                - (Required) "Allow" or "Deny".
  - `protocol`              - (Required) "Tcp", "Udp", "Icmp", "Esp", "Ah", or "*".
  - `source_port_range`     / `source_port_ranges`      - Source port(s).
  - `destination_port_range`/ `destination_port_ranges`  - Destination port(s).
  - `source_address_prefix` / `source_address_prefixes`  - Source CIDR(s).
  - `destination_address_prefix` / `destination_address_prefixes` - Destination CIDR(s).
  - `source_application_security_group_ids`      - (Optional) Source ASG IDs.
  - `destination_application_security_group_ids` - (Optional) Destination ASG IDs.
  - `description`           - (Optional) Rule description.
  EOT
  type = map(list(object({
    name                                       = string
    priority                                   = number
    direction                                  = string
    access                                     = string
    protocol                                   = string
    source_port_range                          = optional(string)
    destination_port_range                     = optional(string)
    source_address_prefix                      = optional(string)
    destination_address_prefix                 = optional(string)
    source_port_ranges                         = optional(list(string))
    destination_port_ranges                    = optional(list(string))
    source_address_prefixes                    = optional(list(string))
    destination_address_prefixes               = optional(list(string))
    source_application_security_group_ids      = optional(list(string))
    destination_application_security_group_ids = optional(list(string))
    description                                = optional(string)
  })))
  nullable = false

  validation {
    condition = alltrue(flatten([
      for nsg_key, rules in var.nsgs : [
        for rule in rules : contains(["Inbound", "Outbound"], rule.direction)
      ]
    ]))
    error_message = "Security rule direction must be either \"Inbound\" or \"Outbound\"."
  }

  validation {
    condition = alltrue(flatten([
      for nsg_key, rules in var.nsgs : [
        for rule in rules : contains(["Allow", "Deny"], rule.access)
      ]
    ]))
    error_message = "Security rule access must be either \"Allow\" or \"Deny\"."
  }

  validation {
    condition = alltrue(flatten([
      for nsg_key, rules in var.nsgs : [
        for rule in rules : contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol)
      ]
    ]))
    error_message = "Security rule protocol must be one of: \"Tcp\", \"Udp\", \"Icmp\", \"Esp\", \"Ah\", or \"*\"."
  }

  validation {
    condition = alltrue(flatten([
      for nsg_key, rules in var.nsgs : [
        for rule in rules : rule.priority >= 100 && rule.priority <= 4096
      ]
    ]))
    error_message = "Security rule priority must be between 100 and 4096."
  }

  validation {
    condition = alltrue([
      for nsg_key, rules in var.nsgs :
      length(rules) == length(distinct([for r in rules : r.priority]))
    ])
    error_message = "Each NSG's security rule priorities must be unique within that NSG. Azure rejects duplicates with an opaque error at apply time — caught here at plan time."
  }

  validation {
    condition = alltrue([
      for nsg_key in keys(var.nsgs) :
      can(regex("^[a-z0-9][a-z0-9-]{1,30}$", nsg_key))
    ])
    error_message = "Each NSG map key must match `^[a-z0-9][a-z0-9-]{1,30}$` (2 to 31 chars, lowercase letters/digits/hyphens, start with alnum). This matches the house naming convention enforced by the in-repo `Naming` submodule. Convert underscores to hyphens, e.g. `nsg_b` -> `nsg-b`."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply to all NSGs"
}
