###############################################################
# MODULE: VNetPeering - Main
# Description: Creates Azure VNet peerings (bidirectional pairs)
###############################################################

resource "azurerm_virtual_network_peering" "this" {
  for_each = var.peerings

  name                                   = coalesce(each.value.name, each.key)
  resource_group_name                    = each.value.resource_group_name
  virtual_network_name                   = each.value.virtual_network_name
  remote_virtual_network_id              = each.value.remote_virtual_network_id
  allow_forwarded_traffic                = each.value.allow_forwarded_traffic
  allow_gateway_transit                  = each.value.allow_gateway_transit
  allow_virtual_network_access           = each.value.allow_virtual_network_access
  use_remote_gateways                    = each.value.use_remote_gateways
  triggers                               = length(each.value.triggers) > 0 ? each.value.triggers : null
  peer_complete_virtual_networks_enabled = each.value.peer_complete_virtual_networks_enabled
  local_subnet_names                     = length(each.value.local_subnet_names) > 0 ? each.value.local_subnet_names : null
  remote_subnet_names                    = length(each.value.remote_subnet_names) > 0 ? each.value.remote_subnet_names : null
  only_ipv6_peering_enabled              = each.value.only_ipv6_peering_enabled
}
