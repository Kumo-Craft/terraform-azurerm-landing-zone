# ═══════════════════════════════════════════════════════════════════════════════
# VARIABLES — Virtual Hubs, VNet Connections & BGP
# ═══════════════════════════════════════════════════════════════════════════════

variable "virtual_hubs" {
  description = <<-EOT
    Map of Virtual Hubs to create.

    routes[*].next_hop_resource_id must be the full ARM resource ID of an existing
    hub virtual network connection (e.g. /subscriptions/.../hubVirtualNetworkConnections/...).
    It is NOT an IP address — the IP semantic belongs to the legacy inline azurerm_virtual_hub
    route block which does NOT apply to azurerm_virtual_hub_route_table.
  EOT
  type = map(object({
    address_prefix                   = string
    location                         = optional(string)
    sku                              = optional(string, "Standard")
    hub_routing_preference           = optional(string, "ExpressRoute")
    branch_to_branch_traffic_enabled = optional(bool)
    routes = optional(list(object({
      address_prefixes     = list(string)
      next_hop_resource_id = string
    })), [])

    # Management Lock on the hub
    lock = optional(object({
      kind = string
      name = optional(string)
    }))

    # VPN Gateway configuration
    vpn_gateway = optional(object({
      scale_unit                            = optional(number, 1)
      bgp_route_translation_for_nat_enabled = optional(bool, false)
      routing_preference                    = optional(string, "Microsoft Network")
      lock = optional(object({
        kind = string
        name = optional(string)
      }))
    }))

    # ExpressRoute Gateway configuration
    express_route_gateway = optional(object({
      scale_units                   = optional(number, 1)
      allow_non_virtual_wan_traffic = optional(bool, false)
      lock = optional(object({
        kind = string
        name = optional(string)
      }))
    }))

    # Azure Firewall configuration
    firewall = optional(object({
      sku_name           = optional(string, "AZFW_Hub")
      sku_tier           = optional(string, "Standard")
      firewall_policy_id = optional(string)
      dns_servers        = optional(list(string))
      private_ip_ranges  = optional(set(string))
      # Secure-by-default: threat intelligence-based filtering in "Alert and deny"
      # mode (provider value "Deny"). Microsoft Zero Trust / Well-Architected and
      # the Secure-Firewall guidance recommend "Alert and deny" so known-malicious
      # IPs/FQDNs/URLs are blocked, not merely alerted (addresses the intent of
      # Checkov CKV_AZURE_216). Overridable to "Alert"/"Off".
      # NOTE: "Deny" requires sku_tier Standard or Premium — Basic supports alert
      # only (guarded by the validation below). Default sku_tier here is Standard.
      threat_intel_mode = optional(string, "Deny")
      zones             = optional(set(string))
      public_ip_count   = optional(number, 1)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for h in var.virtual_hubs :
      contains(["Standard", "Basic"], h.sku)
    ])
    error_message = "virtual_hubs[*].sku must be one of: Standard, Basic."
  }

  validation {
    condition = alltrue([
      for h in var.virtual_hubs :
      h.vpn_gateway == null || h.vpn_gateway.routing_preference == null ||
      contains(["Microsoft Network", "Internet"], h.vpn_gateway.routing_preference)
    ])
    error_message = "virtual_hubs[*].vpn_gateway.routing_preference must be one of: \"Microsoft Network\", \"Internet\"."
  }

  validation {
    condition = alltrue([
      for h in var.virtual_hubs : alltrue([
        for r in coalesce(h.routes, []) :
        can(regex("^/subscriptions/", r.next_hop_resource_id))
      ])
    ])
    error_message = "routes[*].next_hop_resource_id must be a full Azure resource ID starting with /subscriptions/ (typically a hub virtual network connection ID). It is NOT an IP address — that's the legacy inline route semantic which doesn't apply to azurerm_virtual_hub_route_table."
  }

  validation {
    condition = alltrue([
      for h in var.virtual_hubs :
      contains(["ExpressRoute", "VpnGateway", "ASPath"], h.hub_routing_preference)
    ])
    error_message = "virtual_hubs[*].hub_routing_preference must be one of: ExpressRoute, VpnGateway, ASPath."
  }

  validation {
    condition = alltrue([
      for h in var.virtual_hubs :
      h.lock == null || contains(["CanNotDelete", "ReadOnly"], h.lock.kind)
    ])
    error_message = "virtual_hubs[*].lock.kind must be CanNotDelete or ReadOnly."
  }

  validation {
    condition = alltrue([
      for h in var.virtual_hubs :
      h.vpn_gateway == null || h.vpn_gateway.lock == null ||
      contains(["CanNotDelete", "ReadOnly"], h.vpn_gateway.lock.kind)
    ])
    error_message = "virtual_hubs[*].vpn_gateway.lock.kind must be CanNotDelete or ReadOnly."
  }

  validation {
    condition = alltrue([
      for h in var.virtual_hubs :
      h.express_route_gateway == null || h.express_route_gateway.lock == null ||
      contains(["CanNotDelete", "ReadOnly"], h.express_route_gateway.lock.kind)
    ])
    error_message = "virtual_hubs[*].express_route_gateway.lock.kind must be CanNotDelete or ReadOnly."
  }

  validation {
    condition = alltrue([for h in values(var.virtual_hubs) :
      h.firewall == null || (h.firewall.public_ip_count >= 1 && h.firewall.public_ip_count <= 250)
    ])
    error_message = "Each virtual_hubs[*].firewall.public_ip_count must be between 1 and 250 (Azure Firewall PIP limit)."
  }

  validation {
    condition = alltrue([for h in values(var.virtual_hubs) :
      h.firewall == null || contains(["Off", "Alert", "Deny"], h.firewall.threat_intel_mode)
    ])
    error_message = "virtual_hubs[*].firewall.threat_intel_mode must be one of: Off, Alert, Deny."
  }

  validation {
    # Azure Firewall Basic tier supports threat-intel alert mode only; "Deny"
    # requires Standard or Premium. Enforce so the secure default doesn't produce
    # an invalid Basic + Deny combination.
    condition = alltrue([for h in values(var.virtual_hubs) :
      h.firewall == null || h.firewall.sku_tier != "Basic" || h.firewall.threat_intel_mode != "Deny"
    ])
    error_message = "virtual_hubs[*].firewall.threat_intel_mode cannot be \"Deny\" when firewall.sku_tier is \"Basic\" (Basic tier supports alert mode only); use Standard or Premium, or set threat_intel_mode to \"Alert\"/\"Off\"."
  }
}

variable "virtual_hub_connections" {
  description = "Map of Virtual Hub VNet connections"
  type = map(object({
    virtual_hub_key           = string
    remote_virtual_network_id = string
    internet_security_enabled = optional(bool, false)

    routing = optional(object({
      associated_route_table_id                   = optional(string)
      inbound_route_map_id                        = optional(string)
      outbound_route_map_id                       = optional(string)
      static_vnet_local_route_override_criteria   = optional(string)
      static_vnet_propagate_static_routes_enabled = optional(bool, true)

      propagated_route_table = optional(object({
        labels          = optional(set(string))
        route_table_ids = optional(list(string))
      }))

      static_vnet_route = optional(list(object({
        name                = string
        address_prefixes    = set(string)
        next_hop_ip_address = optional(string)
      })), [])
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for c in var.virtual_hub_connections :
      c.routing == null ||
      c.routing.static_vnet_local_route_override_criteria == null ||
      contains(["Contains", "Equal"], c.routing.static_vnet_local_route_override_criteria)
    ])
    error_message = "virtual_hub_connections[*].routing.static_vnet_local_route_override_criteria must be \"Contains\" or \"Equal\"."
  }
}

variable "bgp_connections" {
  description = "Map of Virtual Hub BGP connections (NVA peering)"
  type = map(object({
    virtual_hub_key            = string
    virtual_hub_connection_key = string
    peer_asn                   = number
    peer_ip                    = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for c in var.bgp_connections :
      !contains([65515, 65516, 65517, 65518, 65519, 65520, 12076], c.peer_asn)
    ])
    error_message = "bgp_connections[*].peer_asn cannot use Azure-reserved ASNs (65515-65520, 12076)."
  }
}

variable "express_route_connections" {
  description = "Map of ExpressRoute Connections binding an ExpressRoute circuit AzurePrivatePeering to a hub ER Gateway"
  type = map(object({
    virtual_hub_key                  = string
    express_route_circuit_peering_id = string
    authorization_key                = optional(string)
    routing_weight                   = optional(number, 0)
    internet_security_enabled        = optional(bool, false)
  }))
  default = {}
}
