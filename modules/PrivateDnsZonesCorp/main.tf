###############################################################
# MODULE: PrivateDnsZonesCorp - Main
# Description: Corporate Azure Private DNS zones
#              (non-privatelink) linked to one or more VNets.
#              Used for resolving Azure-hosted FQDNs from VNet
#              clients (e.g. az.epttst.lu for AKS / VM names).
#              RG is caller-provided (v0.2.9+).
###############################################################

resource "time_static" "time" {}

locals {
  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  zone_vnet_pairs = {
    for pair in flatten([
      for zone in var.zones : [
        for link_name, link in var.virtual_network_links : {
          zone                        = zone
          link_name                   = link_name
          virtual_network_resource_id = link.virtual_network_resource_id
          registration_enabled        = link.registration_enabled
        }
      ]
    ]) : "${pair.zone}-${pair.link_name}" => pair
  }
}

###############################################################
# RESOURCE: Private DNS Zones
###############################################################
resource "azurerm_private_dns_zone" "this" {
  for_each = var.zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

###############################################################
# RESOURCE: VNet Links (zone <-> VNet many-to-many)
###############################################################
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  # Composite key `${pair.zone}-${pair.link_name}` ensures Terraform-side uniqueness
  # across the (zone × VNet link) cross-product. Azure-side resource name is
  # `link-${link_name}` (no zone) — same link_name across different zones is
  # intentional since Azure scopes VNet links to their parent zone.
  for_each = local.zone_vnet_pairs

  name                  = "link-${each.value.link_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone].name
  virtual_network_id    = each.value.virtual_network_resource_id
  registration_enabled  = each.value.registration_enabled
  tags                  = local.common_tags
}
