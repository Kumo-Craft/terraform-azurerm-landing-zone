###############################################################
# MODULE: NetworkWatcher - Main
# Description: Azure Network Watcher
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule
# (wrapper around Azure/naming/azurerm).
#
# Convention (unchanged from previous implementation):
#   nw-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:
#   nw-mgm-nprd-gwc-platform
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
  name = var.name != null ? var.name : module.naming["this"].result.network_watcher.name
}

###############################################################
# RESOURCE: Network Watcher
###############################################################
resource "azurerm_network_watcher" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_network_watcher.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
