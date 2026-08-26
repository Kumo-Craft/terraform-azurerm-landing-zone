###############################################################
# MODULE: PrivateDnsZones - Variables
###############################################################

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
  nullable    = false
  description = "Existing resource group name (caller-provided). PrivateDnsZones v0.2.9 no longer creates the RG — caller must supply an existing one (typically via ../ResourceGroup in their root module)."
}

variable "resource_group_id" {
  type        = string
  nullable    = false
  description = "Existing resource group resource ID (caller-provided). Wired as `parent_id` to the AVM ptn module. Caller usually obtains this from their ../ResourceGroup module call (e.g. `module.dns_rg.id`)."
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "virtual_network_links" {
  type = map(object({
    virtual_network_resource_id = string
    resolution_policy           = optional(string)
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
  VNets to link to all DNS zones. Key = logical name, value.virtual_network_resource_id = VNet resource ID.

  resolution_policy (optional): "Default" | "NxDomainRedirect". NxDomainRedirect = "fallback to
  internet" on the VNet link — when an authoritative NXDOMAIN is returned for a private-link zone,
  the Azure recursive resolver retries public recursion. The AVM module only applies a non-Default
  policy to zones that actually support Private Link; zones that don't support it silently ignore
  it, so a blanket NxDomainRedirect is safe. Requires Microsoft.Network API 2024-06-01+ (the AVM
  module already targets a compatible version).
  EOT

  validation {
    condition = alltrue([
      for l in values(var.virtual_network_links) :
      l.resolution_policy == null || contains(["Default", "NxDomainRedirect"], l.resolution_policy)
    ])
    error_message = "Each virtual_network_links[*].resolution_policy must be null, \"Default\", or \"NxDomainRedirect\"."
  }
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional management lock on the hosting resource group (passes through to the AVM ptn module). Standard house shape — kind in {CanNotDelete, ReadOnly}."

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be CanNotDelete or ReadOnly when lock is set."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags"
}
