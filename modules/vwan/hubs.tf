# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL HUBS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_virtual_hub" "hubs" {
  for_each = var.virtual_hubs

  name                             = "${local.wan_name}-hub-${each.key}"
  resource_group_name              = var.resource_group_name
  location                         = coalesce(each.value.location, var.location)
  virtual_wan_id                   = azurerm_virtual_wan.vwan.id
  address_prefix                   = each.value.address_prefix
  sku                              = each.value.sku
  hub_routing_preference           = each.value.hub_routing_preference
  branch_to_branch_traffic_enabled = each.value.branch_to_branch_traffic_enabled

  tags = var.tags

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # Hub destruction cascades all spoke connectivity through this hub + attached
  # gateways/firewalls. Per-hub-instance protection via for_each.
  lifecycle {
    prevent_destroy = true
  }
}

module "hub_lock" {
  source = "../ResourceLock"

  locks = {
    for k, h in var.virtual_hubs : k => {
      scope      = azurerm_virtual_hub.hubs[k].id
      lock_level = h.lock.kind
      name       = h.lock.name
    } if h.lock != null
  }
}

resource "azurerm_virtual_hub_route_table" "default" {
  for_each = {
    for k, v in var.virtual_hubs : k => v
    if length(v.routes) > 0
  }

  name           = "customRouteTable-${each.key}"
  virtual_hub_id = azurerm_virtual_hub.hubs[each.key].id

  dynamic "route" {
    for_each = each.value.routes

    content {
      name              = "route-${route.key}"
      destinations_type = "CIDR"
      destinations      = route.value.address_prefixes
      next_hop_type     = "ResourceId"
      next_hop          = route.value.next_hop_resource_id
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL HUB VNET CONNECTIONS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_virtual_hub_connection" "connections" {
  for_each = var.virtual_hub_connections

  name                      = "${local.wan_name}-conn-${each.key}"
  virtual_hub_id            = azurerm_virtual_hub.hubs[each.value.virtual_hub_key].id
  remote_virtual_network_id = each.value.remote_virtual_network_id
  internet_security_enabled = each.value.internet_security_enabled

  dynamic "routing" {
    for_each = each.value.routing != null ? [each.value.routing] : []
    content {
      associated_route_table_id                   = routing.value.associated_route_table_id
      inbound_route_map_id                        = routing.value.inbound_route_map_id
      outbound_route_map_id                       = routing.value.outbound_route_map_id
      static_vnet_local_route_override_criteria   = routing.value.static_vnet_local_route_override_criteria
      static_vnet_propagate_static_routes_enabled = routing.value.static_vnet_propagate_static_routes_enabled

      dynamic "propagated_route_table" {
        for_each = routing.value.propagated_route_table != null ? [routing.value.propagated_route_table] : []
        content {
          labels          = propagated_route_table.value.labels
          route_table_ids = propagated_route_table.value.route_table_ids
        }
      }

      dynamic "static_vnet_route" {
        for_each = routing.value.static_vnet_route
        content {
          name                = static_vnet_route.value.name
          address_prefixes    = static_vnet_route.value.address_prefixes
          next_hop_ip_address = static_vnet_route.value.next_hop_ip_address
        }
      }
    }
  }
}
