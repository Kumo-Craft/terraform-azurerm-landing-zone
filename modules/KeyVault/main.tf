###############################################################
# MODULE: KeyVault - Main
# Description: Azure Key Vault with lock and role assignments
# Note: Use the separate PrivateEndpoint module for PE
###############################################################

resource "time_static" "time" {}

data "azurerm_client_config" "current" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule
# (wrapper around Azure/naming/azurerm).
#
# Convention (unchanged from previous implementation):
#   kv-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:
#   kv-api-prod-gwc-apim
#
# Note: the upstream Azure/naming/azurerm module enforces the
# Azure Key Vault 24-char ceiling natively — no manual length
# checks needed past the optional `name` override validator.
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
  name                               = var.name != null ? var.name : module.naming["this"].result.key_vault.name
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

###############################################################
# RESOURCE: Key Vault
###############################################################
resource "azurerm_key_vault" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
  sku_name            = var.sku_name

  # Always set explicitly (default true). This also covers the Key Vault
  # control-plane API 2026-02-01 retirement (old versions retire 2027-02-27):
  # from that API version new vaults default to RBAC, but because we pass
  # rbac_authorization_enabled explicitly the behaviour is deterministic
  # whichever control-plane API version the azurerm provider calls. The only
  # residual action is keeping azurerm current (tracked by the Renovate watcher)
  # so the provider targets API 2026-02-01+ before the deadline.
  rbac_authorization_enabled = var.enable_rbac

  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_template_deployment = var.enabled_for_template_deployment

  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  public_network_access_enabled = var.public_network_access_enabled

  dynamic "network_acls" {
    for_each = var.network_acls != null ? [var.network_acls] : []
    content {
      default_action             = network_acls.value.default_action
      bypass                     = network_acls.value.bypass
      ip_rules                   = network_acls.value.ip_rules
      virtual_network_subnet_ids = network_acls.value.subnet_ids
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_key_vault.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: RBAC — Current deployer (convenience, scalar)
# Delegated to ../RoleAssignment for single source of truth.
###############################################################
module "deployer_rbac" {
  source = "../RoleAssignment"
  count  = var.assign_rbac_to_current_user ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  # principal_type left at the module default ("ServicePrincipal") since the
  # deployer is typically a pipeline SP. Override at the variable level if
  # this module is consumed by a human user account.
}

# v0.2.82 sweep: drive-by Truth 4 fix — module.deployer_rbac is count-gated
# (count = var.assign_rbac_to_current_user ? 1 : 0). Static moved.to address
# must include [0] index. Same bug pattern as FinOpsHub v0.2.49 F-3 +
# PaloCluster v0.2.73 F-2/F-4.
moved {
  from = azurerm_role_assignment.deployer
  to   = module.deployer_rbac[0].azurerm_role_assignment.this
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = azurerm_key_vault.this.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}

moved {
  from = azurerm_role_assignment.this
  to   = module.role_assignments.azurerm_role_assignment.this
}
