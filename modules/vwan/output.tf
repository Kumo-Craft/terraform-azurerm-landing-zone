# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL WAN OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "resource" {
  description = "The complete Virtual WAN resource object"
  value       = azurerm_virtual_wan.vwan
}

output "virtual_wan_id" {
  description = "ID of the Virtual WAN"
  value       = azurerm_virtual_wan.vwan.id
}

output "virtual_wan_name" {
  description = "Name of the Virtual WAN"
  value       = azurerm_virtual_wan.vwan.name
}

# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL HUB OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "virtual_hub_ids" {
  description = "Map of Virtual Hub IDs"
  value       = { for k, v in azurerm_virtual_hub.hubs : k => v.id }
}

output "virtual_hub_names" {
  description = "Map of Virtual Hub names"
  value       = { for k, v in azurerm_virtual_hub.hubs : k => v.name }
}

output "lock_ids" {
  description = "Map of WAN-level Resource Lock IDs (passes through module.lock.ids)."
  value       = module.lock.ids
}

output "hub_lock_ids" {
  description = "Map of hub key => Resource Lock ID for the hub (only entries with lock configured)."
  value       = module.hub_lock.ids
}

output "vpn_gateway_lock_ids" {
  description = "Map of hub key => Resource Lock ID for the VPN Gateway (only entries with lock configured)."
  value       = module.vpn_gateway_lock.ids
}

output "er_gateway_lock_ids" {
  description = "Map of hub key => Resource Lock ID for the ER Gateway (only entries with lock configured)."
  value       = module.er_gateway_lock.ids
}

output "virtual_hub_default_route_table_ids" {
  description = "Map of Virtual Hub default route table IDs"
  value       = { for k, v in azurerm_virtual_hub.hubs : k => v.default_route_table_id }
}

output "virtual_hub_router_ips" {
  description = "Map of hub key => list of vHub virtual router BGP peer IPs (computed by Azure post-provisioning). PaloCluster uses these to configure BGP neighbors on the Palo side."
  value       = { for k, v in azurerm_virtual_hub.hubs : k => v.virtual_router_ips }
}

output "virtual_hub_router_asns" {
  description = "Map of hub key => vHub virtual router BGP ASN (computed by Azure, typically 65515). PaloCluster uses this to configure BGP neighbor ASN on the Palo side."
  value       = { for k, v in azurerm_virtual_hub.hubs : k => v.virtual_router_asn }
}

# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL HUB CONNECTION OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "virtual_hub_connection_ids" {
  description = "Map of Virtual Hub Connection IDs"
  value       = { for k, v in azurerm_virtual_hub_connection.connections : k => v.id }
}

# ═══════════════════════════════════════════════════════════════════════════════
# VPN GATEWAY OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "vpn_gateway_ids" {
  description = "Map of VPN Gateway IDs"
  value       = { for k, v in azurerm_vpn_gateway.hub_vpn_gateways : k => v.id }
}

output "vpn_gateway_bgp_settings" {
  description = "Map of VPN Gateway BGP settings"
  value = {
    for k, v in azurerm_vpn_gateway.hub_vpn_gateways : k => {
      asn               = v.bgp_settings[0].asn
      peer_weight       = v.bgp_settings[0].peer_weight
      instance_0_bgp_ip = try(tolist(v.bgp_settings[0].instance_0_bgp_peering_address[0].default_ips)[0], null)
      instance_1_bgp_ip = try(tolist(v.bgp_settings[0].instance_1_bgp_peering_address[0].default_ips)[0], null)
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXPRESS ROUTE GATEWAY OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "express_route_gateway_ids" {
  description = "Map of ExpressRoute Gateway IDs"
  value       = { for k, v in azurerm_express_route_gateway.hub_er_gateways : k => v.id }
}

output "express_route_connection_ids" {
  description = "Map of ExpressRoute Connection IDs (circuit peering ↔ hub ER GW)"
  value       = { for k, v in azurerm_express_route_connection.hub_er_connections : k => v.id }
}

# ═══════════════════════════════════════════════════════════════════════════════
# FIREWALL OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "firewall_ids" {
  description = "Map of Azure Firewall IDs"
  value       = { for k, v in azurerm_firewall.hub_firewalls : k => v.id }
}

output "firewall_private_ips" {
  description = "Map of Azure Firewall private IP addresses"
  value       = { for k, v in azurerm_firewall.hub_firewalls : k => v.virtual_hub[0].private_ip_address }
}

# ═══════════════════════════════════════════════════════════════════════════════
# P2S GATEWAY OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "vpn_server_configuration_ids" {
  description = "Map of VPN Server Configuration IDs"
  value       = { for k, v in azurerm_vpn_server_configuration.configs : k => v.id }
}

output "p2s_gateway_ids" {
  description = "Map of Point-to-Site VPN Gateway IDs"
  value       = { for k, v in azurerm_point_to_site_vpn_gateway.p2s_gateways : k => v.id }
}

# ═══════════════════════════════════════════════════════════════════════════════
# BGP CONNECTION OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "bgp_connection_ids" {
  description = "Map of Virtual Hub BGP Connection IDs"
  value       = { for k, v in azurerm_virtual_hub_bgp_connection.bgp : k => v.id }
}

# ═══════════════════════════════════════════════════════════════════════════════
# VPN SITE OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "vpn_site_ids" {
  description = "Map of VPN Site IDs"
  value       = { for k, v in azurerm_vpn_site.sites : k => v.id }
}

# ═══════════════════════════════════════════════════════════════════════════════
# VPN CONNECTION OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "vpn_connection_ids" {
  description = "Map of VPN Connection IDs"
  value       = { for k, v in azurerm_vpn_gateway_connection.connections : k => v.id }
}

output "vpn_gateway_public_ips" {
  description = "Map of VPN Gateway public IP addresses (instance 0 and 1) — needed for on-premises CPE configuration"
  value = {
    for k, v in azurerm_vpn_gateway.hub_vpn_gateways : k => {
      instance_0_ip = try([for ip in tolist(v.bgp_settings[0].instance_0_bgp_peering_address[0].tunnel_ips) : ip if !can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", ip))][0], null)
      instance_1_ip = try([for ip in tolist(v.bgp_settings[0].instance_1_bgp_peering_address[0].tunnel_ips) : ip if !can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", ip))][0], null)
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RBAC OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════

output "role_assignment_ids" {
  description = "Map of role assignment logical key => role assignment ID"
  value       = { for k, v in module.rbac : k => v.id }
}
