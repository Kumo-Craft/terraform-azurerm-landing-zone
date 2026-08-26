# ═══════════════════════════════════════════════════════════════════════════════
# VPN SERVER CONFIGURATIONS (Point-to-Site)
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_vpn_server_configuration" "configs" {
  for_each = var.vpn_server_configurations

  name                     = "${local.wan_name}-vpnconf-${each.key}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  vpn_authentication_types = each.value.vpn_authentication_types
  vpn_protocols            = each.value.vpn_protocols

  dynamic "client_root_certificate" {
    for_each = each.value.client_root_certificates

    content {
      name             = client_root_certificate.value.name
      public_cert_data = client_root_certificate.value.public_cert_data
    }
  }

  dynamic "azure_active_directory_authentication" {
    for_each = each.value.azure_active_directory_authentication != null ? [each.value.azure_active_directory_authentication] : []

    content {
      audience = azure_active_directory_authentication.value.audience
      issuer   = azure_active_directory_authentication.value.issuer
      tenant   = azure_active_directory_authentication.value.tenant
    }
  }

  tags = var.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# POINT-TO-SITE VPN GATEWAYS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_point_to_site_vpn_gateway" "p2s_gateways" {
  for_each = var.p2s_gateways

  name                        = "${local.wan_name}-p2sgw-${each.key}"
  resource_group_name         = var.resource_group_name
  location                    = azurerm_virtual_hub.hubs[each.value.virtual_hub_key].location
  virtual_hub_id              = azurerm_virtual_hub.hubs[each.value.virtual_hub_key].id
  vpn_server_configuration_id = azurerm_vpn_server_configuration.configs[each.value.vpn_server_configuration_key].id
  scale_unit                  = each.value.scale_unit
  dns_servers                 = each.value.dns_servers

  connection_configuration {
    name = each.value.connection_configuration.name

    vpn_client_address_pool {
      address_prefixes = each.value.connection_configuration.client_address_prefixes
    }
  }

  tags = var.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL HUB BGP CONNECTIONS (NVA peering)
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_virtual_hub_bgp_connection" "bgp" {
  for_each = var.bgp_connections

  name                          = "${local.wan_name}-bgp-${each.key}"
  virtual_hub_id                = azurerm_virtual_hub.hubs[each.value.virtual_hub_key].id
  peer_asn                      = each.value.peer_asn
  peer_ip                       = each.value.peer_ip
  virtual_network_connection_id = azurerm_virtual_hub_connection.connections[each.value.virtual_hub_connection_key].id
}

# ═══════════════════════════════════════════════════════════════════════════════
# VPN SITES
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_vpn_site" "sites" {
  for_each = var.vpn_sites

  name                = "${local.wan_name}-site-${each.key}"
  location            = azurerm_virtual_hub.hubs[each.value.virtual_hub_key].location
  resource_group_name = var.resource_group_name
  virtual_wan_id      = azurerm_virtual_wan.vwan.id
  address_cidrs       = each.value.address_cidrs
  device_vendor       = each.value.device_vendor
  device_model        = each.value.device_model

  dynamic "link" {
    for_each = each.value.links

    content {
      name          = link.value.name
      ip_address    = link.value.ip_address
      fqdn          = link.value.fqdn
      speed_in_mbps = link.value.speed_in_mbps
      provider_name = link.value.provider_name

      dynamic "bgp" {
        for_each = link.value.bgp != null ? [link.value.bgp] : []

        content {
          asn             = bgp.value.asn
          peering_address = bgp.value.peering_address
        }
      }
    }
  }

  tags = var.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# VPN CONNECTIONS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_vpn_gateway_connection" "connections" {
  for_each = nonsensitive(var.vpn_connections)

  name                      = "${local.wan_name}-conn-${each.key}"
  vpn_gateway_id            = azurerm_vpn_gateway.hub_vpn_gateways[each.value.virtual_hub_key].id
  remote_vpn_site_id        = azurerm_vpn_site.sites[each.value.vpn_site_key].id
  internet_security_enabled = each.value.internet_security_enabled

  dynamic "routing" {
    for_each = each.value.routing != null ? [each.value.routing] : []

    content {
      associated_route_table = coalesce(routing.value.associated_route_table, azurerm_virtual_hub.hubs[each.value.virtual_hub_key].default_route_table_id)

      dynamic "propagated_route_table" {
        for_each = routing.value.propagated_route_tables != null ? [routing.value.propagated_route_tables] : []

        content {
          route_table_ids = propagated_route_table.value.route_table_ids
          labels          = propagated_route_table.value.labels
        }
      }
    }
  }

  dynamic "vpn_link" {
    for_each = each.value.vpn_links

    content {
      name                                  = vpn_link.value.name
      vpn_site_link_id                      = azurerm_vpn_site.sites[each.value.vpn_site_key].link[vpn_link.key].id
      bandwidth_mbps                        = vpn_link.value.bandwidth_mbps
      bgp_enabled                           = vpn_link.value.bgp_enabled
      connection_mode                       = vpn_link.value.connection_mode
      protocol                              = vpn_link.value.protocol
      ratelimit_enabled                     = vpn_link.value.ratelimit_enabled
      route_weight                          = vpn_link.value.route_weight
      shared_key                            = vpn_link.value.shared_key
      local_azure_ip_address_enabled        = vpn_link.value.local_azure_ip_address_enabled
      policy_based_traffic_selector_enabled = vpn_link.value.policy_based_traffic_selector_enabled

      dynamic "custom_bgp_address" {
        for_each = vpn_link.value.custom_bgp_address != null ? vpn_link.value.custom_bgp_address : []

        content {
          ip_address          = custom_bgp_address.value.ip_address
          ip_configuration_id = custom_bgp_address.value.ip_configuration_id
        }
      }

      dynamic "ipsec_policy" {
        for_each = vpn_link.value.ipsec_policy != null ? [vpn_link.value.ipsec_policy] : []

        content {
          dh_group                 = ipsec_policy.value.dh_group
          ike_encryption_algorithm = ipsec_policy.value.ike_encryption_algorithm
          ike_integrity_algorithm  = ipsec_policy.value.ike_integrity_algorithm
          encryption_algorithm     = ipsec_policy.value.encryption_algorithm
          integrity_algorithm      = ipsec_policy.value.integrity_algorithm
          pfs_group                = ipsec_policy.value.pfs_group
          sa_data_size_kb          = ipsec_policy.value.sa_data_size_kb
          sa_lifetime_sec          = ipsec_policy.value.sa_lifetime_sec
        }
      }
    }
  }
}
