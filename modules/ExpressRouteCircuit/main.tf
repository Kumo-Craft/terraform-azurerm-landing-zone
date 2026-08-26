###############################################################
# MODULE: ExpressRouteCircuit - Main
# Description: ExpressRoute circuit with optional Azure Private
#              Peering. Service key is exposed as an output so it
#              can be shared with the provider (DE-CIX, Equinix…).
###############################################################

resource "time_static" "time" {}

# Naming — delegated to the in-repo Naming submodule (XOR escape hatch).
# Convention: erc-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    erc-con-prod-gwc-backbone
# Slug "erc" is the canonical upstream prefix from Azure/naming/azurerm.
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name = var.name != null ? var.name : module.naming["this"].result.express_route_circuit.name
}

resource "azurerm_express_route_circuit" "this" {
  name                  = local.name
  location              = var.location
  resource_group_name   = var.resource_group_name
  service_provider_name = var.service_provider_name
  peering_location      = var.peering_location
  bandwidth_in_mbps     = var.bandwidth_in_mbps

  sku {
    tier   = var.sku_tier
    family = var.sku_family
  }

  allow_classic_operations = var.allow_classic_operations

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic
  # sweep). ExpressRoute circuit destruction severs on-prem connectivity +
  # requires carrier coordination + new provisioning time to restore. Same
  # systemic protection as ApplicationGateway v0.2.81 + DdosProtection v0.2.79
  # + ResourceGroup v0.2.76 + AlzManagement v0.2.77 + KeyVault + Aks +
  # ContainerRegistry. Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_express_route_circuit_peering" "private" {
  count = var.private_peering != null ? 1 : 0

  peering_type                  = "AzurePrivatePeering"
  express_route_circuit_name    = azurerm_express_route_circuit.this.name
  resource_group_name           = var.resource_group_name
  peer_asn                      = var.private_peering.peer_asn
  primary_peer_address_prefix   = var.private_peering.primary_peer_address_prefix
  secondary_peer_address_prefix = var.private_peering.secondary_peer_address_prefix
  vlan_id                       = var.private_peering.vlan_id
  shared_key                    = var.private_peering.shared_key
  ipv4_enabled                  = var.private_peering.ipv4_enabled
}

resource "azurerm_express_route_circuit_peering" "microsoft" {
  count = var.microsoft_peering != null ? 1 : 0

  peering_type                  = "MicrosoftPeering"
  express_route_circuit_name    = azurerm_express_route_circuit.this.name
  resource_group_name           = var.resource_group_name
  peer_asn                      = var.microsoft_peering.peer_asn
  primary_peer_address_prefix   = var.microsoft_peering.primary_peer_address_prefix
  secondary_peer_address_prefix = var.microsoft_peering.secondary_peer_address_prefix
  vlan_id                       = var.microsoft_peering.vlan_id
  shared_key                    = var.microsoft_peering.shared_key
  ipv4_enabled                  = var.microsoft_peering.ipv4_enabled

  microsoft_peering_config {
    advertised_public_prefixes = var.microsoft_peering.microsoft_peering_config.advertised_public_prefixes
    advertised_communities     = var.microsoft_peering.microsoft_peering_config.advertised_communities
    customer_asn               = var.microsoft_peering.microsoft_peering_config.customer_asn
    routing_registry_name      = var.microsoft_peering.microsoft_peering_config.routing_registry_name
  }
}

module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_express_route_circuit.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
