###############################################################
# MODULE: RouteTable - Main
# Description: Azure Route Table with routes and management lock
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# Convention: route-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    route-con-prod-gwc-default
# Slug "route" is the canonical upstream prefix from Azure/naming/azurerm v0.4.3.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name = var.name != null ? var.name : module.naming["this"].result.route_table.name
}

###############################################################
# RESOURCE: Route Table
###############################################################
resource "azurerm_route_table" "this" {
  name                          = local.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = var.bgp_route_propagation_enabled

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Routes (separate resources, keyed by var.routes key)
#
# Architectural choice (v0.2.7): routes are separate `azurerm_route`
# resources instead of an inline `dynamic "route"` block. This enables
# clean state migration when consumed via composition from other Stack
# modules (e.g. NetworkStack), where the upstream state already uses
# separate route resources.
###############################################################
resource "azurerm_route" "this" {
  for_each = var.routes

  name                   = each.value.name
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = each.value.next_hop_in_ip_address
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_route_table.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
