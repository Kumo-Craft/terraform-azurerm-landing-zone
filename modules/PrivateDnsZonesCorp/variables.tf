###############################################################
# MODULE: PrivateDnsZonesCorp - Variables
###############################################################

variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Existing resource group name (caller-provided). PrivateDnsZonesCorp v0.2.9 no longer creates the RG — caller must supply an existing one."
}

variable "zones" {
  type        = set(string)
  description = "Set of corporate private DNS zone names to host on Azure (e.g. [\"az.epttst.lu\"])."
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for z in var.zones :
      can(regex("^([a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", z))
    ])
    error_message = "Each zone must be a lowercase FQDN (e.g. \"az.epttst.lu\"). Labels must be 1-63 chars, start/end with alphanumeric, and may contain hyphens; the TLD is 2-63 letters. Trailing dots are not allowed."
  }
}

variable "virtual_network_links" {
  type = map(object({
    virtual_network_resource_id = string
    registration_enabled        = optional(bool, false)
  }))
  description = "Map of logical name => VNet link config. Each VNet is linked to every zone."
  default     = {}
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}
