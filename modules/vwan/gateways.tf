# ═══════════════════════════════════════════════════════════════════════════════
# VPN GATEWAYS IN VIRTUAL HUBS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_vpn_gateway" "hub_vpn_gateways" {
  for_each = {
    for k, v in var.virtual_hubs : k => v
    if v.vpn_gateway != null
  }

  name                                  = "${local.wan_name}-vpngw-${each.key}"
  location                              = azurerm_virtual_hub.hubs[each.key].location
  resource_group_name                   = var.resource_group_name
  virtual_hub_id                        = azurerm_virtual_hub.hubs[each.key].id
  scale_unit                            = each.value.vpn_gateway.scale_unit
  bgp_route_translation_for_nat_enabled = each.value.vpn_gateway.bgp_route_translation_for_nat_enabled
  routing_preference                    = each.value.vpn_gateway.routing_preference

  tags = var.tags
}

module "vpn_gateway_lock" {
  source = "../ResourceLock"

  locks = {
    for k, h in var.virtual_hubs : k => {
      scope      = azurerm_vpn_gateway.hub_vpn_gateways[k].id
      lock_level = h.vpn_gateway.lock.kind
      name       = h.vpn_gateway.lock.name
    } if h.vpn_gateway != null && h.vpn_gateway.lock != null
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXPRESS ROUTE GATEWAYS IN VIRTUAL HUBS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_express_route_gateway" "hub_er_gateways" {
  for_each = {
    for k, v in var.virtual_hubs : k => v
    if v.express_route_gateway != null
  }

  name                          = "${local.wan_name}-ergw-${each.key}"
  location                      = azurerm_virtual_hub.hubs[each.key].location
  resource_group_name           = var.resource_group_name
  virtual_hub_id                = azurerm_virtual_hub.hubs[each.key].id
  scale_units                   = each.value.express_route_gateway.scale_units
  allow_non_virtual_wan_traffic = each.value.express_route_gateway.allow_non_virtual_wan_traffic

  tags = var.tags
}

module "er_gateway_lock" {
  source = "../ResourceLock"

  locks = {
    for k, h in var.virtual_hubs : k => {
      scope      = azurerm_express_route_gateway.hub_er_gateways[k].id
      lock_level = h.express_route_gateway.lock.kind
      name       = h.express_route_gateway.lock.name
    } if h.express_route_gateway != null && h.express_route_gateway.lock != null
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXPRESS ROUTE CONNECTIONS (CIRCUIT PEERING ↔ HUB ER GATEWAY)
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_express_route_connection" "hub_er_connections" {
  for_each = var.express_route_connections

  name                             = "${local.wan_name}-erconn-${each.key}"
  express_route_gateway_id         = azurerm_express_route_gateway.hub_er_gateways[each.value.virtual_hub_key].id
  express_route_circuit_peering_id = each.value.express_route_circuit_peering_id
  authorization_key                = each.value.authorization_key
  routing_weight                   = each.value.routing_weight
  internet_security_enabled        = each.value.internet_security_enabled
}

# ═══════════════════════════════════════════════════════════════════════════════
# AZURE FIREWALL IN VIRTUAL HUBS
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_firewall" "hub_firewalls" {
  for_each = {
    for k, v in var.virtual_hubs : k => v
    if v.firewall != null
  }

  name                = "${local.wan_name}-fw-${each.key}"
  location            = azurerm_virtual_hub.hubs[each.key].location
  resource_group_name = var.resource_group_name
  sku_name            = each.value.firewall.sku_name
  sku_tier            = each.value.firewall.sku_tier
  firewall_policy_id  = each.value.firewall.firewall_policy_id
  dns_servers         = each.value.firewall.dns_servers
  private_ip_ranges   = each.value.firewall.private_ip_ranges
  # Secure-by-default "Deny" (Alert and deny) — see var.virtual_hubs.firewall.threat_intel_mode.
  # CKV_AZURE_216 proper targets azurerm_firewall_policy (threat_intelligence_mode); this module
  # attaches an external policy via firewall_policy_id and does not define one, so the equivalent
  # control this resource owns (threat_intel_mode) is set to the secure "Deny" default.
  threat_intel_mode = each.value.firewall.threat_intel_mode
  zones             = each.value.firewall.zones

  virtual_hub {
    virtual_hub_id  = azurerm_virtual_hub.hubs[each.key].id
    public_ip_count = each.value.firewall.public_ip_count
  }

  tags = var.tags

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # Hub firewall destruction severs ALL East-West + North-South traffic inspection
  # for the hub. SNAT port allocation table loss = active session disruption.
  # Per-firewall-instance protection via for_each.
  lifecycle {
    prevent_destroy = true
  }
}
