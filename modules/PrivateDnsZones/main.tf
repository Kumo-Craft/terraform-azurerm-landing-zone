###############################################################
# MODULE: PrivateDnsZones - Main
# Description: All Azure Private Link DNS Zones via the AVM
#              pattern module. RG is caller-provided (v0.2.9+).
###############################################################

resource "time_static" "time" {}

###############################################################
# MODULE: AVM — Private Link Private DNS Zones
###############################################################
module "private_dns_zones" {
  source  = "Azure/avm-ptn-network-private-link-private-dns-zones/azurerm"
  version = "~> 0.23"

  location         = var.location
  parent_id        = var.resource_group_id
  enable_telemetry = false
  lock             = var.lock

  virtual_network_link_default_virtual_networks = var.virtual_network_links

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}
