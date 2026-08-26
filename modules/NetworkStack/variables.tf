###############################################################
# MODULE: NetworkStack - Variables
#
# Generic spoke (or hub) network bundle: RG + Network Watcher + vnet
# + Route Table (default to NVA) + NSGs + Subnets (1-shot azapi to
# satisfy "Subnets must have NSG" policy).
#
# Designed to host any workload — AVD pooled, AKS, App Service,
# generic VMs, NetApp, Bastion, dedicated PE subnets, etc.
###############################################################

###############################################################
# NAMING
# Defaults follow the {prefix}-{acr}-{env}-{region_code}-{suffix} pattern.
# Each component name can be overridden explicitly.
###############################################################
variable "subscription_acronym" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload suffix for vnet name (e.g. spoke, hub, nva, avd, aks)."
  default     = "spoke"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.workload))
    error_message = "workload must start with a letter; lowercase alphanumeric + hyphen, max 31 chars."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type     = string
  nullable = false
}

###############################################################
# RESOURCE GROUP
# NetworkStack v0.2.8 no longer creates or looks up a resource group.
# Caller must provide an existing one via resource_group_name.
###############################################################
variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Existing resource group name. NetworkStack v0.2.8 no longer creates the RG — caller must provide an existing one (create via ../ResourceGroup in your root module if needed)."
}

###############################################################
# NETWORK WATCHER (1 per region per subscription is sufficient)
###############################################################
variable "create_network_watcher" {
  type        = bool
  description = "Create a Network Watcher in the RG. Set false if one already exists in this region of this subscription (NW is regional, AzureNetworkWatcherRG is the historical default)."
  default     = true
}

variable "network_watcher_name" {
  type        = string
  description = "Override Network Watcher name. Default: nw-{prefix}-{workload}."
  default     = null
}

###############################################################
# VIRTUAL NETWORK
###############################################################
variable "vnet_name" {
  type        = string
  description = "Override vnet name. Default: vnet-{subscription_acronym}-{environment}-{region_code}-{workload} via ../Naming. Set this to use a legacy / externally-managed name."
  default     = null

  validation {
    condition = (
      var.vnet_name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `vnet_name` must be set (legacy override), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "vnet_address_space" {
  type        = list(string)
  description = "vnet CIDR block(s)."
  nullable    = false

  validation {
    condition     = length(var.vnet_address_space) > 0
    error_message = "At least one address space is required."
  }
}

variable "dns_servers" {
  type        = list(string)
  description = "Custom DNS servers. Empty/null = Azure-provided DNS. For hub-and-spoke with NVA DNS proxy or Azure DNS Private Resolver, set this to the proxy/inbound endpoint IP."
  default     = null
}

variable "ddos_protection_plan_id" {
  type        = string
  description = "DDoS Standard plan ID to associate. Null = no DDoS Standard (basic free tier only)."
  default     = null
}

variable "encryption_enforcement" {
  type        = string
  description = "vnet-level encryption (preview/limited regions). 'AllowUnencrypted' (default) or 'DropUnencrypted' to enforce encrypted-only east-west traffic. Null = no encryption block (Azure default)."
  default     = null

  validation {
    condition     = var.encryption_enforcement == null || contains(["AllowUnencrypted", "DropUnencrypted"], var.encryption_enforcement)
    error_message = "encryption_enforcement must be 'AllowUnencrypted', 'DropUnencrypted', or null."
  }
}

variable "flow_timeout_in_minutes" {
  type        = number
  description = "Connection idle timeout (4-30 min). Useful when long-running connections must survive Azure's default 4 min idle timeout."
  default     = null

  validation {
    condition     = var.flow_timeout_in_minutes == null || (var.flow_timeout_in_minutes >= 4 && var.flow_timeout_in_minutes <= 30)
    error_message = "flow_timeout_in_minutes must be between 4 and 30."
  }
}

###############################################################
# ROUTE TABLE
# By default a UDR table is created. Setting create_route_table=false
# skips it (e.g. for hub vnets that own routing in the NVA itself).
# Default route is created only when default_route_next_hop_ip is set.
###############################################################
variable "create_route_table" {
  type        = bool
  description = "Create a route table and attach it to subnets that opt in (subnets[].attach_route_table=true)."
  default     = true
}

variable "route_table_name" {
  type        = string
  description = "Override route table name. Default: rt-{prefix}-{workload}."
  default     = null
}

variable "default_route_next_hop_type" {
  type        = string
  description = "Next hop type for the default 0.0.0.0/0 route."
  default     = "VirtualAppliance"

  validation {
    condition     = contains(["VirtualAppliance", "VirtualNetworkGateway", "Internet", "VnetLocal", "None"], var.default_route_next_hop_type)
    error_message = "default_route_next_hop_type must be a valid Azure next-hop type."
  }
}

variable "default_route_next_hop_ip" {
  type        = string
  description = "IP address for the default route next hop (typically the NVA ILB front-end). Null = no default route created."
  default     = null
}

variable "extra_routes" {
  type = map(object({
    address_prefix         = string
    next_hop_type          = string
    next_hop_in_ip_address = optional(string)
  }))
  description = "Additional UDRs beyond the default route. Map key = route name suffix."
  default     = {}
  nullable    = false
}

variable "bgp_route_propagation_enabled" {
  type        = bool
  description = "Allow Virtual Network Gateway BGP routes to propagate. False (default) ensures UDRs win."
  default     = false
}

###############################################################
# SUBNETS
#
# Each subnet is created via azapi_resource (single PUT) so the NSG
# attachment is atomic with creation — required by ALZ policy
# 'Deny-Subnet-Without-Nsg'.
#
# Special-case subnets (Bastion / Gateway / Firewall) MUST opt out
# of NSG attachment via create_nsg=false / attach_route_table=false
# per Azure rules.
###############################################################
variable "subnets" {
  description = <<-EOT
  Map of subnets. Map key is the short subnet identifier used in NSG / subnet
  naming when no explicit `name` is supplied.

  - `cidr`                              - (Required) Subnet CIDR.
  - `name`                              - (Optional) Override subnet name. Default: snet-{prefix}-{key}. Use 'AzureBastionSubnet', 'GatewaySubnet', 'AzureFirewallSubnet' as appropriate.
  - `create_nsg`                        - (Optional, default true) Create + attach an NSG. Set false for GatewaySubnet (Azure forbids). For AzureBastionSubnet you may need a custom NSG with specific rules.
  - `nsg_rules`                         - (Optional) Inline NSG rules (see security_rule schema). Empty = relies on Azure default rules.
  - `attach_route_table`                - (Optional, default true) Attach the module's shared route table. Set false for GatewaySubnet (Azure forbids), and false when using per-subnet `routes` (mutually exclusive).
  - `routes`                            - (Optional) Per-subnet dedicated route table. Map of {address_prefix, next_hop_type, next_hop_in_ip_address?} keyed by route name. When set, the module creates a DEDICATED route table `rt-{prefix}-{key}` holding ONLY these routes (NO default 0.0.0.0/0) and attaches it to this subnet. Use for subnets where a default route is forbidden but specific routes are allowed — e.g. an Entra Domain Services subnet. Requires `attach_route_table = false` (exclusive with the shared route table).
  - `delegation`                        - (Optional) {name, service_name} for managed services (AKS apiserver, NetApp, App Service, ContainerInstance, etc.).
  - `service_endpoints`                 - (Optional) List of service endpoints (e.g. ["Microsoft.Storage", "Microsoft.KeyVault"]).
  - `private_endpoint_network_policies` - (Optional, default "Enabled") Set "Disabled" for subnets hosting Private Endpoints if you don't want NSG to apply to PE NICs (legacy behavior).
  - `default_outbound_access_enabled`   - (Optional, default false) Microsoft retires default outbound access in Sept 2025. Keep false to be future-proof; use NAT Gateway / NVA for explicit egress.
  - `nat_gateway_id`                     - (Optional) Resource ID of a NAT Gateway to associate with this subnet for explicit outbound (SNAT). Pairs with `default_outbound_access_enabled = false`. Azure forbids a NAT Gateway on GatewaySubnet / AzureFirewallSubnet.
  EOT
  type = map(object({
    cidr               = string
    name               = optional(string)
    create_nsg         = optional(bool, true)
    attach_route_table = optional(bool, true)
    routes = optional(map(object({
      address_prefix         = string
      next_hop_type          = string
      next_hop_in_ip_address = optional(string)
    })))
    nsg_rules = optional(list(object({
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
    })), [])
    delegation = optional(object({
      name         = string
      service_name = string
    }))
    service_endpoints                 = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Enabled")
    default_outbound_access_enabled   = optional(bool, false)
    nat_gateway_id                    = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for s in var.subnets :
      can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$", s.cidr))
    ])
    error_message = "Each subnet cidr must be a valid CIDR block (e.g. 10.0.1.0/24)."
  }

  validation {
    condition = alltrue([
      for s in var.subnets :
      contains(["Enabled", "Disabled"], s.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be 'Enabled' or 'Disabled'."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      !v.create_nsg || can(regex("^[a-z0-9][a-z0-9-]{1,30}$", k))
    ])
    error_message = "Subnet keys used with create_nsg=true must match ^[a-z0-9][a-z0-9-]{1,30}$ (forwarded as NSG map keys; the ../NSG module enforces this regex). Use a lowercase identifier for the key and set the Azure-side subnet name via the `name` field, e.g. key='bastion' with name='AzureBastionSubnet'."
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets :
      !(v.attach_route_table && v.routes != null && length(v.routes) > 0)
    ])
    error_message = "A subnet cannot set both attach_route_table=true and routes (mutually exclusive). When using a per-subnet dedicated route table via `routes`, set attach_route_table=false."
  }
}

###############################################################
# HUB PEERING (optional)
###############################################################
variable "hub_peering" {
  description = <<-EOT
  Optional spoke-to-hub VNet peering created inside this module. Default null
  = no peering (caller must declare it separately, e.g. via the VNetPeering
  module). When set, NetworkStack creates the spoke->hub peering inline so
  the network deployment is self-contained.

  The reverse hub->spoke peering still lives in the connectivity sub
  (aggregator pattern: 1 hub VNet ↔ N spokes). Both sides must be applied
  for the peering to reach 'Connected' state.

  Cross-sub peering: the module's deployer SP needs Network Contributor on
  the hub VNet's RG. allow_forwarded_traffic = true is typical for
  hub-and-spoke with NVA (Palo) so the hub can forward spoke traffic.
  EOT
  type = object({
    name                      = string
    remote_virtual_network_id = string
    allow_forwarded_traffic   = optional(bool, true)
    allow_gateway_transit     = optional(bool, false)
    use_remote_gateways       = optional(bool, false)
  })
  default = null
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources created by the module (RG, NW, vnet, RT, NSGs, subnets)."
  default     = {}
}
