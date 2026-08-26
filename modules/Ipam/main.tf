###############################################################
# Ipam - Azure Virtual Network Manager IPAM
###############################################################
# Creates (optional): a Network Manager (AVNM) + hierarchical
# IPAM pools + fixed static CIDRs. IPAM is available on any AVNM
# instance regardless of scope_accesses; this module can also
# attach pools to an existing AVNM (create_network_manager=false).
#
# Non-overlap across pools is enforced by AVNM itself; enforce
# usage of pool-allocated space via Azure Policy downstream.
###############################################################

module "naming" {
  source               = "../Naming"
  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  # acr-env-region-workload — used to compose pool names (upstream
  # Azure/naming has no ipam_pool type, so we slug it ourselves).
  name_suffix = join("-", module.naming.suffix)

  network_manager_name = coalesce(var.network_manager_name, module.naming.result.network_manager.name)

  # Id of the AVNM the pools hang off — created here or brought in.
  network_manager_id = var.create_network_manager ? azurerm_network_manager.this[0].id : var.existing_network_manager_id

  # Resolved pool name per key (override or derived slug).
  pool_names = {
    for k, v in var.pools : k => coalesce(v.name, "ipam-${k}-${local.name_suffix}")
  }

  # Split into two tiers so a real dependency edge orders children after
  # their parent. Terraform forbids a for_each resource from referencing
  # its own instances, so the hierarchy is modelled as root -> child
  # across two resource blocks (validated: a child's parent must be root).
  root_pools  = { for k, v in var.pools : k => v if v.parent_pool_key == null }
  child_pools = { for k, v in var.pools : k => v if v.parent_pool_key != null }

  # Pool id per key, whichever tier created it — for static-CIDR lookup + outputs.
  pool_ids = merge(
    { for k, r in azurerm_network_manager_ipam_pool.root : k => r.id },
    { for k, r in azurerm_network_manager_ipam_pool.child : k => r.id },
  )

  # Flatten static CIDRs into a single map keyed "poolKey/cidrKey".
  static_cidrs = merge([
    for pk, pv in var.pools : {
      for ck, cv in pv.static_cidrs :
      "${pk}/${ck}" => {
        pool_key                           = pk
        name                               = coalesce(cv.name, ck)
        address_prefixes                   = cv.address_prefixes
        number_of_ip_addresses_to_allocate = cv.number_of_ip_addresses_to_allocate
      }
    }
  ]...)
}

# ── Network Manager (AVNM) — optional ────────────────────────
resource "azurerm_network_manager" "this" {
  count = var.create_network_manager ? 1 : 0

  name                = local.network_manager_name
  location            = var.location
  resource_group_name = var.resource_group_name
  scope_accesses      = var.network_manager_scope_accesses
  description         = var.network_manager_description

  scope {
    management_group_ids = var.network_manager_scope.management_group_ids
    subscription_ids     = var.network_manager_scope.subscription_ids
  }

  tags = var.tags
}

# ── IPAM pools — tier 1 (roots, no parent) ───────────────────
resource "azurerm_network_manager_ipam_pool" "root" {
  for_each = local.root_pools

  name               = local.pool_names[each.key]
  network_manager_id = local.network_manager_id
  location           = var.location
  address_prefixes   = each.value.address_prefixes
  display_name       = coalesce(each.value.display_name, each.key)
  description        = each.value.description

  tags = var.tags
}

# ── IPAM pools — tier 2 (children of a root pool) ────────────
resource "azurerm_network_manager_ipam_pool" "child" {
  for_each = local.child_pools

  name               = local.pool_names[each.key]
  network_manager_id = local.network_manager_id
  location           = var.location
  address_prefixes   = each.value.address_prefixes
  display_name       = coalesce(each.value.display_name, each.key)
  description        = each.value.description

  # Reference the root pool's name attribute → real dependency edge, so the
  # parent is created before the child (the API rejects an unknown parent).
  parent_pool_name = azurerm_network_manager_ipam_pool.root[each.value.parent_pool_key].name

  tags = var.tags
}

# ── Static CIDRs carved out of a pool ────────────────────────
resource "azurerm_network_manager_ipam_pool_static_cidr" "this" {
  for_each = local.static_cidrs

  name         = each.value.name
  ipam_pool_id = local.pool_ids[each.value.pool_key]

  # Exactly one of the two is set (enforced by var.pools validation).
  address_prefixes                   = each.value.address_prefixes
  number_of_ip_addresses_to_allocate = each.value.number_of_ip_addresses_to_allocate
}
