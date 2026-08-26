###############################################################
# MODULE: SubnetWithNsg - Variables
###############################################################

variable "virtual_network_id" {
  type        = string
  description = "The full resource ID of the virtual network."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.virtual_network_id))
    error_message = "virtual_network_id must be a valid Azure Virtual Network resource ID."
  }
}

variable "subnets" {
  description = <<-EOT
  List of subnets to create with NSG attached in a single API call.
  Uses azapi_resource to comply with Azure Policy "Subnets must have a NSG".

  - `name`                              - (Required) Subnet name.
  - `address_prefixes`                  - (Required) List of CIDR blocks (e.g. ["10.0.0.0/24"]). Supports dual-stack (IPv4 + IPv6) and multi-CIDR subnets.
  - `nsg_id`                            - (Optional) NSG resource ID to associate.
  - `route_table_id`                    - (Optional) Route Table resource ID to associate.
  - `nat_gateway_id`                    - (Optional) NAT Gateway resource ID. Cannot be set on the AzureFirewallSubnet, GatewaySubnet, AzureBastionSubnet.
  - `service_endpoints`                 - (Optional) List of service endpoints (e.g. ["Microsoft.Storage", "Microsoft.KeyVault"]). Empty = none.
  - `private_endpoint_network_policies` - (Optional) "Enabled", "Disabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled". Default "Disabled" (recommended for PE-hosting subnets; some PEs require this set to Disabled).
  - `default_outbound_access_enabled`   - (Optional) Enable default outbound access. Defaults to false (best practice; outbound through NAT/firewall instead).
  - `ip_address_pool`                   - (Optional) IPAM pool allocation for the subnet. Mutually exclusive with address_prefixes.
  - `delegation`                        - (DEPRECATED, use `delegations`) Single service delegation. Merged with `delegations` if both set.
  - `delegations`                       - (Optional) List of service delegations. Replaces `delegation`. Most subnets need at most one, but the schema allows several.
  - `lock`                              - (Optional) Management lock for this subnet. Kind must be "CanNotDelete" or "ReadOnly".
  - `role_assignments`                  - (Optional) Map of role assignments scoped to this subnet.
  EOT
  type = list(object({
    name                              = string
    address_prefixes                  = optional(list(string), [])
    nsg_id                            = optional(string)
    route_table_id                    = optional(string)
    nat_gateway_id                    = optional(string)
    service_endpoints                 = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Disabled")
    default_outbound_access_enabled   = optional(bool, false)
    ip_address_pool = optional(object({
      id                     = string
      number_of_ip_addresses = number
    }))
    delegation = optional(object({
      name         = string
      service_name = string
    }))
    delegations = optional(list(object({
      name         = string
      service_name = string
    })), [])
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "ServicePrincipal")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
  }))
  nullable = false

  validation {
    condition = alltrue([
      for s in var.subnets :
      length(s.address_prefixes) >= 1 || s.ip_address_pool != null
    ])
    error_message = "Each subnet must have at least one address_prefixes entry or an ip_address_pool specified."
  }

  validation {
    condition     = length(var.subnets) == length(distinct([for s in var.subnets : s.name]))
    error_message = "Each subnet name must be unique."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      contains(["Enabled", "Disabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], s.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be one of: Enabled, Disabled, NetworkSecurityGroupEnabled, RouteTableEnabled."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      s.nat_gateway_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/natGateways/[^/]+$", s.nat_gateway_id))
    ])
    error_message = "Each nat_gateway_id, when set, must be a valid Azure NAT Gateway resource ID."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      s.ip_address_pool == null || can(regex("^/subscriptions/[^/]+/", s.ip_address_pool.id))
    ])
    error_message = "Each ip_address_pool.id, when set, must be a valid Azure resource ID."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      s.ip_address_pool == null || s.ip_address_pool.number_of_ip_addresses > 0
    ])
    error_message = "Each ip_address_pool.number_of_ip_addresses, when set, must be greater than 0."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      s.lock == null || contains(["CanNotDelete", "ReadOnly"], s.lock.kind)
    ])
    error_message = "Each subnet lock.kind must be \"CanNotDelete\" or \"ReadOnly\"."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      alltrue([
        for ra in values(s.role_assignments) :
        contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)
      ])
    ])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      length(concat(
        s.delegation != null ? [s.delegation.name] : [],
        [for d in s.delegations : d.name]
        )) == length(distinct(concat(
          s.delegation != null ? [s.delegation.name] : [],
          [for d in s.delegations : d.name]
      )))
    ])
    error_message = "Each subnet's effective delegation set (combining deprecated 'delegation' + 'delegations[*]') must have unique names. Azure rejects duplicate delegation names at apply."
  }
}
