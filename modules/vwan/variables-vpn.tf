# ═══════════════════════════════════════════════════════════════════════════════
# VARIABLES — VPN Sites, Connections, P2S & Server Configurations
# ═══════════════════════════════════════════════════════════════════════════════

variable "vpn_sites" {
  description = "Map of VPN Sites to create"
  type = map(object({
    virtual_hub_key = string
    address_cidrs   = optional(set(string))
    device_vendor   = optional(string)
    device_model    = optional(string)

    links = list(object({
      name          = string
      ip_address    = optional(string)
      fqdn          = optional(string)
      speed_in_mbps = optional(number, 100)
      provider_name = optional(string)

      bgp = optional(object({
        asn             = number
        peering_address = string
      }))
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for s in var.vpn_sites : alltrue([
        for l in s.links :
        l.bgp == null || !contains([65515, 65516, 65517, 65518, 65519, 65520, 12076], l.bgp.asn)
      ])
    ])
    error_message = "vpn_sites[*].links[*].bgp.asn cannot use Azure-reserved ASNs (65515-65520, 12076)."
  }

  validation {
    condition = alltrue([for s in values(var.vpn_sites) :
      (s.address_cidrs != null && length(s.address_cidrs) > 0) ||
      anytrue([for l in coalesce(s.links, []) : l.bgp != null])
    ])
    error_message = "Each vpn_site must have either address_cidrs (non-empty) OR at least one link with bgp configured. Azure API rejects vpn_sites with neither."
  }
}

variable "vpn_connections" {
  description = "Map of VPN Site connections to Virtual Hubs. Marked sensitive because vpn_links[*].shared_key (pre-shared key) is a credential — Terraform will suppress this variable's value in plan/apply output."
  sensitive   = true
  type = map(object({
    vpn_site_key    = string
    virtual_hub_key = string

    internet_security_enabled = optional(bool, true)

    routing = optional(object({
      associated_route_table = optional(string)
      propagated_route_tables = optional(object({
        route_table_ids = optional(list(string), [])
        labels          = optional(list(string), ["default"])
      }))
    }))

    vpn_links = list(object({
      name                                  = string
      bandwidth_mbps                        = optional(number, 100)
      bgp_enabled                           = optional(bool, false)
      connection_mode                       = optional(string, "Default")
      protocol                              = optional(string, "IKEv2")
      ratelimit_enabled                     = optional(bool, false)
      route_weight                          = optional(number, 0)
      shared_key                            = optional(string)
      local_azure_ip_address_enabled        = optional(bool, false)
      policy_based_traffic_selector_enabled = optional(bool, false)

      custom_bgp_address = optional(list(object({
        ip_address          = string
        ip_configuration_id = string
      })))

      ipsec_policy = optional(object({
        dh_group                 = string
        ike_encryption_algorithm = string
        ike_integrity_algorithm  = string
        encryption_algorithm     = string
        integrity_algorithm      = string
        pfs_group                = string
        sa_data_size_kb          = number
        sa_lifetime_sec          = number
      }))
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for c in var.vpn_connections : alltrue([
        for l in c.vpn_links :
        contains(["IKEv2", "IKEv1"], l.protocol)
      ])
    ])
    error_message = "vpn_connections[*].vpn_links[*].protocol must be one of: IKEv2, IKEv1."
  }

  validation {
    condition = alltrue([for c in values(var.vpn_connections) :
      alltrue([for l in c.vpn_links :
        l.shared_key == null || length(l.shared_key) >= 8
      ])
    ])
    error_message = "Each vpn_connections[*].vpn_links[*].shared_key must be at least 8 characters when set (Azure min 1, MS Learn + IETF RFC 3947 recommend 8+ alphanumeric+symbols)."
  }
}

variable "vpn_server_configurations" {
  description = "Map of VPN Server Configurations (for Point-to-Site)"
  type = map(object({
    vpn_authentication_types = optional(list(string), ["Certificate"])
    vpn_protocols            = optional(list(string))

    client_root_certificates = optional(map(object({
      name             = string
      public_cert_data = string
    })), {})

    azure_active_directory_authentication = optional(object({
      audience = string
      issuer   = string
      tenant   = string
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for c in var.vpn_server_configurations : alltrue([
        for t in c.vpn_authentication_types :
        contains(["Certificate", "Radius", "AAD"], t)
      ])
    ])
    error_message = "vpn_server_configurations[*].vpn_authentication_types must only contain: Certificate, Radius, AAD."
  }

  validation {
    condition = alltrue([
      for c in var.vpn_server_configurations :
      !contains(c.vpn_authentication_types, "AAD") || c.azure_active_directory_authentication != null
    ])
    error_message = "vpn_server_configurations with \"AAD\" must set azure_active_directory_authentication (audience, issuer, tenant)."
  }

  validation {
    condition = alltrue([
      for c in var.vpn_server_configurations :
      c.vpn_protocols == null || alltrue([for p in coalesce(c.vpn_protocols, []) : contains(["IkeV2", "OpenVPN"], p)])
    ])
    error_message = "vpn_server_configurations[*].vpn_protocols must only contain: IkeV2, OpenVPN."
  }
}

variable "p2s_gateways" {
  description = "Map of Point-to-Site VPN Gateways"
  type = map(object({
    virtual_hub_key              = string
    vpn_server_configuration_key = string
    scale_unit                   = optional(number, 1)
    dns_servers                  = optional(list(string), [])

    connection_configuration = object({
      name                    = string
      client_address_prefixes = list(string)
    })
  }))
  default = {}
}
