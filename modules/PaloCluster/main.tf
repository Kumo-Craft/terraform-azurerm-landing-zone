###############################################################
# Module PaloCluster — Palo Alto VM-Series Firewall Cluster
###############################################################
# Creates a complete cluster:
#   - Internal Load Balancer (trust, HA ports)
#   - VM-Series instances (3 NICs each, zonal) — management access via vWAN / Bastion
#   - Backend pool associations (trust NICs -> ILB)
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming — delegated to ../Naming submodule (ILB name only).
# Per-VM names (in the firewalls map) stay literal — they're
# map-shape and the per-key naming is semantic.
#
# Slug "lb" from Azure/naming/azurerm produces prefix "lbi-"
# (load_balancer_internal). The "-trust" suffix is appended
# to indicate this is the trust-side ILB.
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
  prefix = "${var.subscription_acronym}-${var.environment}-${var.region_code}"

  # ILB name: Naming-submodule path (var.name == null) or explicit override.
  # The "-trust" suffix marks this as the trust-side ILB.
  ilb_name = var.name != null ? var.name : "${module.naming["this"].result.lb.name}-trust"

  common_tags = merge(
    var.tags,
    {
      CreatedOn    = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
      PanosVersion = var.panos_version
    }
  )
}

###############################################################
# State migration: the previously inlined azurerm_resource_group is
# now caller-provided via var.resource_group_name. This removed block
# releases it from PaloCluster state without destroying it Azure-side.
# Callers upgrading from v0.2.24 must move the RG to a separate
# ../ResourceGroup module call (or equivalent) in their root config.
###############################################################
removed {
  from = azurerm_resource_group.this
  lifecycle {
    destroy = false
  }
}

###############################################################
# Internal Load Balancer — Trust (HA Ports)
###############################################################
resource "azurerm_lb" "trust" {
  name                = local.ilb_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "frontend"
    subnet_id                     = var.subnet_trust_id
    private_ip_address            = var.ilb_frontend_ip
    private_ip_address_allocation = "Static"
  }

  tags = local.common_tags
}

###############################################################
# Management Lock — ILB
###############################################################
module "ilb_lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    "ilb" = {
      scope      = azurerm_lb.trust.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

resource "azurerm_lb_backend_address_pool" "trust" {
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.trust.id
}

resource "azurerm_lb_probe" "trust" {
  name                = "probe-Tcp-${var.ilb_probe_port}"
  loadbalancer_id     = azurerm_lb.trust.id
  protocol            = "Tcp"
  port                = var.ilb_probe_port
  probe_threshold     = var.ilb_probe_threshold
  interval_in_seconds = var.ilb_probe_interval
}

resource "azurerm_lb_rule" "ha_ports" {
  name                           = "rule-ha-ports"
  loadbalancer_id                = azurerm_lb.trust.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.trust.id]
  probe_id                       = azurerm_lb_probe.trust.id
  floating_ip_enabled            = false
}

