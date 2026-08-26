###############################################################
# MODULE: PrivateEndpoint - Variables
###############################################################

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region for Private Endpoints"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for deploying Private Endpoints"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "Subnet ID must be a valid Azure resource ID."
  }
}

###############################################################
# PRIVATE ENDPOINTS
###############################################################
variable "private_endpoints" {
  description = <<-EOT
  A map of Private Endpoint configurations. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  Each entry must set EXACTLY ONE of `resource_id` or `resource_alias`:
  - `resource_id`    targets a regular Azure resource (Key Vault, Storage
    Account, etc.) and uses `private_connection_resource_id` at the
    provider level. Requires `subresource_names` (e.g. ["vault"]).
  - `resource_alias` targets a Private Link Service by alias string
    (e.g. third-party PLS, cross-subscription endpoints) and uses
    `private_connection_resource_alias` at the provider level.
    `subresource_names` is typically empty for alias-based connections.

  Object fields:
  - `name`                           - (Required) Private Endpoint name.
  - `resource_id`                    - (Optional) Target Azure resource ID. Mutually exclusive with `resource_alias`.
  - `resource_alias`                 - (Optional) Private Link Service alias. Mutually exclusive with `resource_id`.
  - `subresource_names`              - (Optional) Subresources to expose (e.g. ["vault"], ["blob"]). Required when `resource_id` is set; ignored for alias-based PEs.
  - `is_manual_connection`           - (Optional) Manual connection requiring approval. Defaults to false.
  - `request_message`                - (Optional) Message for manual connections. NOTE: this string appears in plan output — do NOT embed credentials or tokens.
  - `private_ip_address`             - (Optional) Static private IP address.
  - `member_name`                    - (Optional) Member name for IP config. Defaults to "default".
  - `custom_network_interface_name`  - (Optional) Custom NIC name.
  - `private_dns_zone_group`         - (Optional) DNS zone group configuration.
  - `tags`                           - (Optional) Tags specific to this endpoint.
  EOT
  type = map(object({
    name                          = string
    resource_id                   = optional(string)
    resource_alias                = optional(string)
    subresource_names             = optional(list(string), [])
    is_manual_connection          = optional(bool, false)
    request_message               = optional(string)
    private_ip_address            = optional(string)
    member_name                   = optional(string, "default")
    custom_network_interface_name = optional(string)
    private_dns_zone_group = optional(object({
      name                 = optional(string, "default")
      private_dns_zone_ids = list(string)
    }))
    tags = optional(map(string), {})
  }))
  nullable = false

  validation {
    condition = alltrue([
      for ep in var.private_endpoints :
      (ep.resource_id != null) != (ep.resource_alias != null)
    ])
    error_message = "Each Private Endpoint must set EXACTLY ONE of `resource_id` or `resource_alias` (not both, not neither)."
  }

  validation {
    condition = alltrue([
      for ep in var.private_endpoints :
      ep.resource_alias != null || length(ep.subresource_names) > 0
    ])
    error_message = "subresource_names is required (non-empty list) when `resource_id` is set. Only `resource_alias`-based PEs may omit it."
  }

  validation {
    condition = alltrue([
      for ep in var.private_endpoints :
      ep.resource_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", ep.resource_id))
    ])
    error_message = "resource_id must be a valid Azure resource ID when set."
  }

  validation {
    condition = alltrue([
      for ep in var.private_endpoints :
      ep.private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", ep.private_ip_address))
    ])
    error_message = "private_ip_address must be a valid IPv4 address."
  }

  validation {
    condition = alltrue([
      for ep in var.private_endpoints :
      !ep.is_manual_connection || (ep.request_message != null && ep.request_message != "")
    ])
    error_message = "request_message is required when is_manual_connection is true."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all Private Endpoints"
  default     = {}
  nullable    = false
}
