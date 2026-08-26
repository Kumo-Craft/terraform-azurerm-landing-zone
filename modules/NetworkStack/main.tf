###############################################################
# MODULE: NetworkStack - Main
#
# Composes a regional spoke (or hub) network footprint:
#   Network Watcher (optional) → vnet → Route Table
#   → NSGs → Subnets (azapi single-PUT for ALZ NSG-required policy)
#
# v0.2.8: RG creation removed — caller must supply resource_group_name.
# v0.2.8: NetworkWatcher composed via ../NetworkWatcher module.
#
# Suitable for AVD, AKS, App Service, generic VMs, Bastion, NetApp,
# dedicated PE subnets, or any combination via the subnets map.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming — VNet name delegated to ../Naming submodule (F-6).
# Convention: vnet-{subscription_acronym}-{environment}-{region_code}-{workload}
# RT and NW names keep the inline prefix pattern (rt-/nw-) because
# those prefixes differ from the upstream Azure/naming slug and are
# wired through to the respective child modules via name overrides.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.vnet_name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  prefix = "${var.subscription_acronym}-${var.environment}-${var.region_code}"

  rt_name_default = "rt-${local.prefix}-${var.workload}"
  # v0.2.8: nw_name_default uses var.workload (var.resource_group_workload removed).
  nw_name_default = "nw-${local.prefix}-${var.workload}"
  # NSG naming is now handled by the composed ../NSG module
  # (workload = subnet key, byte-for-byte preserves `nsg-{acr}-{env}-{region}-{key}`)

  vnet_name = var.vnet_name != null ? var.vnet_name : module.naming["this"].result.virtual_network.name
  rt_name   = coalesce(var.route_table_name, local.rt_name_default)
  nw_name   = coalesce(var.network_watcher_name, local.nw_name_default)

  # Subnets that need an NSG created by this module
  subnets_with_nsg = { for k, v in var.subnets : k => v if v.create_nsg }

  # Subnets requesting a DEDICATED route table (non-empty `routes` map).
  # These get rt-{prefix}-{key} with ONLY the declared routes (no 0.0.0.0/0).
  subnets_with_routes = { for k, v in var.subnets : k => v if v.routes != null && length(v.routes) > 0 }

  # Subnet name resolution per entry
  subnet_names = {
    for k, v in var.subnets : k => coalesce(v.name, "snet-${local.prefix}-${k}")
  }

  # Tags merged with CreatedOn for traceability
  effective_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# COMPOSED: Network Watcher (../NetworkWatcher since v0.2.8)
#
# Migrated from inline azurerm_network_watcher to composition.
# State-safe via `moved` block below. Naming preserved byte-for-byte
# via the var.name override (local.nw_name = nw-{prefix}-{workload}
# — matches NetworkWatcher module's own Naming submodule output for
# the same standard inputs, AND lets callers override via the existing
# var.network_watcher_name).
#
# Note: Azure also auto-creates one named NetworkWatcher_<region>
# in AzureNetworkWatcherRG. Set create_network_watcher=false if
# you intend to consume that one or already have your own.
###############################################################
module "network_watcher" {
  count  = var.create_network_watcher ? 1 : 0
  source = "../NetworkWatcher"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
  location             = var.location
  resource_group_name  = var.resource_group_name

  name = local.nw_name
  tags = local.effective_tags
}

moved {
  from = azurerm_network_watcher.this[0]
  to   = module.network_watcher[0].azurerm_network_watcher.this
}

###############################################################
# RESOURCE: Virtual Network
###############################################################
resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name

  address_space           = var.vnet_address_space
  dns_servers             = var.dns_servers
  flow_timeout_in_minutes = var.flow_timeout_in_minutes

  dynamic "ddos_protection_plan" {
    for_each = var.ddos_protection_plan_id != null ? [1] : []
    content {
      id     = var.ddos_protection_plan_id
      enable = true
    }
  }

  dynamic "encryption" {
    for_each = var.encryption_enforcement != null ? [1] : []
    content {
      enforcement = var.encryption_enforcement
    }
  }

  tags = local.effective_tags
}

###############################################################
# COMPOSED: Route Table (../RouteTable since v0.2.7)
#
# Migrated from inline azurerm_route_table + separate azurerm_route
# resources to composition. State-safe via `moved` blocks below.
# Naming preserved byte-for-byte via the var.name override (rt-* prefix
# matches local.rt_name, NOT the upstream Naming submodule's route-* slug).
###############################################################
module "route_table" {
  count  = var.create_route_table ? 1 : 0
  source = "../RouteTable"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
  location             = var.location
  resource_group_name  = var.resource_group_name

  name                          = local.rt_name
  bgp_route_propagation_enabled = var.bgp_route_propagation_enabled

  routes = merge(
    var.default_route_next_hop_ip != null ? {
      "default-udr" = {
        name                   = "default-udr"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = var.default_route_next_hop_type
        next_hop_in_ip_address = contains(["VirtualAppliance"], var.default_route_next_hop_type) ? var.default_route_next_hop_ip : null
      }
    } : {},
    var.extra_routes
  )

  tags = local.effective_tags
}

###############################################################
# COMPOSED: Per-subnet dedicated Route Tables (../RouteTable)
#
# One dedicated RT per subnet that declares `routes`, named
# rt-{prefix}-{subnet_key}, holding ONLY those routes — NO default
# 0.0.0.0/0. Purpose: subnets where Azure forbids overriding the
# default route but allows specific routes (e.g. Entra Domain
# Services, where MS blocks touching 0.0.0.0/0 but permits UDRs to
# specific prefixes). Mutually exclusive with attach_route_table
# (enforced by a var.subnets validation).
###############################################################
module "subnet_route_table" {
  source   = "../RouteTable"
  for_each = local.subnets_with_routes

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
  location             = var.location
  resource_group_name  = var.resource_group_name

  name                          = "rt-${local.prefix}-${each.key}"
  bgp_route_propagation_enabled = var.bgp_route_propagation_enabled

  routes = {
    for rk, rv in each.value.routes : rk => {
      name                   = rk
      address_prefix         = rv.address_prefix
      next_hop_type          = rv.next_hop_type
      next_hop_in_ip_address = rv.next_hop_in_ip_address
    }
  }

  tags = local.effective_tags
}

moved {
  from = azurerm_route_table.this[0]
  to   = module.route_table[0].azurerm_route_table.this
}

moved {
  from = azurerm_route.default[0]
  to   = module.route_table[0].azurerm_route.this["default-udr"]
}

moved {
  from = azurerm_route.extra
  to   = module.route_table[0].azurerm_route.this
}

###############################################################
# COMPOSED: NSGs (one per subnet that opts in)
# Delegated to ../NSG. NetworkStack used to inline the NSG block
# (Sprint 7 P0 #1 "accept duplication"); since NSG module v0.2.4
# the canonical leaf exposes the same map-shape via `var.nsgs` +
# its 5 validators (direction/access/protocol/priority range +
# priority-uniqueness within each NSG) + the map-shape Naming
# pattern. NetworkStack now composes it to inherit all guards.
#
# Naming is byte-for-byte identical: both the old inline path and
# the new ../NSG composition produce `nsg-{acr}-{env}-{region}-{key}`
# where `{key}` is the subnet map key (the subset of subnets that
# opt in via `create_nsg = true`). State-safe via the `moved` block.
###############################################################
module "nsg" {
  source = "../NSG"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload # not used by NSG naming (map key wins), forwarded for symmetry
  location             = var.location
  resource_group_name  = var.resource_group_name

  nsgs = {
    for k, v in local.subnets_with_nsg : k => v.nsg_rules
  }

  tags = local.effective_tags
}

moved {
  from = azurerm_network_security_group.this
  to   = module.nsg.azurerm_network_security_group.this
}

###############################################################
# RESOURCE: Subnets (azapi single-PUT)
#
# Using azapi instead of azurerm_subnet so the NSG (and RT)
# associations land in the same PUT as the subnet creation —
# required to satisfy 'Subnets must have a NSG' deny policy.
###############################################################
resource "azapi_resource" "subnet" {
  for_each = var.subnets

  type      = "Microsoft.Network/virtualNetworks/subnets@2025-05-01"
  name      = local.subnet_names[each.key]
  parent_id = azurerm_virtual_network.this.id

  body = {
    properties = merge(
      {
        addressPrefixes                = [each.value.cidr]
        defaultOutboundAccess          = each.value.default_outbound_access_enabled
        privateEndpointNetworkPolicies = each.value.private_endpoint_network_policies
      },
      each.value.create_nsg ? {
        networkSecurityGroup = {
          id = module.nsg.ids[each.key]
        }
      } : {},
      # Route table attachment — three-way:
      #   1. subnet declares `routes` → its dedicated RT (no default route);
      #   2. else shared RT when created + opted in (attach_route_table);
      #   3. else nothing.
      (each.value.routes != null && length(each.value.routes) > 0) ? {
        routeTable = {
          id = module.subnet_route_table[each.key].id
        }
        } : (var.create_route_table && each.value.attach_route_table ? {
          routeTable = {
            id = module.route_table[0].id
          }
      } : {}),
      length(each.value.service_endpoints) > 0 ? {
        serviceEndpoints = [for s in each.value.service_endpoints : { service = s }]
      } : {},
      each.value.delegation != null ? {
        delegations = [{
          name = each.value.delegation.name
          properties = {
            serviceName = each.value.delegation.service_name
          }
        }]
      } : {},
      each.value.nat_gateway_id != null ? {
        natGateway = {
          id = each.value.nat_gateway_id
        }
      } : {},
    )
  }

  response_export_values = ["id", "name"]

  lifecycle {
    # ALZ DINE policies may inject privateEndpointNetworkPolicies side-effects;
    # keep authoritative on the explicit set above without fighting policy.
    ignore_changes = [
      body.properties.privateLinkServiceNetworkPolicies,
    ]
  }
}

###############################################################
# HUB PEERING (optional spoke->hub)
#
# Now delegates to ../VNetPeering (composed) instead of inlining the
# resource. Naming preserved byte-for-byte via the new `name` override
# field on the VNetPeering map entry. State-safe via the `moved` block.
#
# The reverse hub->spoke peering must be declared on the hub side
# (connectivity sub) — Azure requires both sides for 'Connected' state.
###############################################################
module "hub_peering" {
  source = "../VNetPeering"

  peerings = var.hub_peering != null ? {
    "hub" = {
      virtual_network_name         = azurerm_virtual_network.this.name
      resource_group_name          = var.resource_group_name
      remote_virtual_network_id    = var.hub_peering.remote_virtual_network_id
      name                         = var.hub_peering.name
      allow_forwarded_traffic      = var.hub_peering.allow_forwarded_traffic
      allow_gateway_transit        = var.hub_peering.allow_gateway_transit
      use_remote_gateways          = var.hub_peering.use_remote_gateways
      allow_virtual_network_access = true
    }
  } : {}
}

moved {
  from = azurerm_virtual_network_peering.hub[0]
  to   = module.hub_peering.azurerm_virtual_network_peering.this["hub"]
}
