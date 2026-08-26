###############################################################
# MODULE: NSG - Main
# Description: Creates multiple Azure Network Security Groups
# Naming: nsg-{subscription_acronym}-{environment}-{region_code}-{key}
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
#
# Map-shape pattern: this module creates N NSGs (one per map key),
# so we instantiate `../Naming` per-entry via `for_each = var.nsgs`,
# passing the map key as the `workload` segment. The canonical
# Naming wraps `Azure/naming/azurerm` whose `network_security_group`
# output uses slug `nsg` — byte-for-byte identical to the prior
# inline literal `"nsg-${acr}-${env}-${region}-${k}"`. State-safe.
#
# First module in the repo to use the map-shape Naming composition;
# pattern reusable for any future map-of-resources module.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.nsgs

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = each.key
}

###############################################################
# RESOURCE: Network Security Groups
###############################################################
resource "azurerm_network_security_group" "this" {
  for_each = var.nsgs

  name                = module.naming[each.key].result.network_security_group.name
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "security_rule" {
    for_each = each.value
    content {
      name      = security_rule.value.name
      priority  = security_rule.value.priority
      direction = security_rule.value.direction
      access    = security_rule.value.access
      protocol  = security_rule.value.protocol

      source_port_range      = security_rule.value.source_port_range
      destination_port_range = security_rule.value.destination_port_range

      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix

      source_port_ranges      = security_rule.value.source_port_ranges
      destination_port_ranges = security_rule.value.destination_port_ranges

      source_address_prefixes      = security_rule.value.source_address_prefixes
      destination_address_prefixes = security_rule.value.destination_address_prefixes

      source_application_security_group_ids      = security_rule.value.source_application_security_group_ids
      destination_application_security_group_ids = security_rule.value.destination_application_security_group_ids

      description = security_rule.value.description
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}
