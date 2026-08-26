# ═══════════════════════════════════════════════════════════════════════════════
# NAMING — delegated to the in-repo Naming submodule
# Convention: vwan-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    vwan-con-prod-gwc-network
# Slug "vwan" is the canonical upstream prefix from Azure/naming/azurerm v0.4.3.
# ═══════════════════════════════════════════════════════════════════════════════

module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  wan_name = var.name != null ? var.name : module.naming["this"].result.virtual_wan.name
}

# ═══════════════════════════════════════════════════════════════════════════════
# VIRTUAL WAN — Core
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_virtual_wan" "vwan" {
  name                              = local.wan_name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  type                              = var.type
  disable_vpn_encryption            = var.disable_vpn_encryption
  allow_branch_to_branch_traffic    = var.allow_branch_to_branch_traffic
  office365_local_breakout_category = var.office365_local_breakout_category

  tags = var.tags

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # vWAN destruction cascades all hubs + firewalls + VPN/ER gateways + spoke
  # egress paths. ALZ-wide outage scenario. Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RESOURCE: Management Lock
# ═══════════════════════════════════════════════════════════════════════════════

module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_virtual_wan.vwan.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

# ═══════════════════════════════════════════════════════════════════════════════
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
# ═══════════════════════════════════════════════════════════════════════════════

module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_virtual_wan.vwan.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
