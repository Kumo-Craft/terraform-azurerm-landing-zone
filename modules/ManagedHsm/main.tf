###############################################################
# MODULE: ManagedHsm - Main
# Description: Azure Key Vault Managed HSM (FIPS 140-3 Level 3,
#              single-tenant HSM pool). One Managed HSM + optional
#              Resource Lock.
#
# ── Notes ──
# - purge_protection_enabled is FORCED to true: mandatory-for-prod per
#   MS guidance and IRREVERSIBLE (cannot be disabled by anyone, incl.
#   Microsoft). Not exposed as a variable.
# - Soft-delete is ALWAYS on (7-90d, immutable once set). A soft-deleted
#   HSM keeps billing until purged, and its (globally unique) name can't
#   be reused until purged.
# - Post-deploy (out of scope): the HSM must be ACTIVATED with a security
#   domain (3-10 KV certs + quorum), then RBAC (Crypto Officer/User) and
#   keys are provisioned at the data plane. To PURGE on destroy you must
#   also set the provider feature toggle:
#     features { key_vault { purge_soft_deleted_hardware_security_modules_on_destroy = true } }
###############################################################

resource "time_static" "time" {}

data "azurerm_client_config" "current" {}

locals {
  # Manual compose (see variables.tf): mhsm-{acr}-{env}-{region}[-{workload}];
  # compact() drops the workload segment when it is null.
  computed_name = "mhsm-${join("-", compact([var.subscription_acronym, var.environment, var.region_code, var.workload]))}"
  name          = coalesce(var.name, local.computed_name)

  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  # Managed HSM local-RBAC built-in role name -> role definition GUID.
  # Source: https://learn.microsoft.com/azure/key-vault/managed-hsm/built-in-roles
  mhsm_builtin_role_ids = {
    "Managed HSM Administrator"                  = "a290e904-7015-4bba-90c8-60543313cdb4"
    "Managed HSM Crypto Officer"                 = "515eb02d-2335-4d2d-92f2-b1cbdf9c3778"
    "Managed HSM Crypto User"                    = "21dbd100-6940-42c2-9190-5d6cb909625b"
    "Managed HSM Policy Administrator"           = "4bd23610-cdcf-4971-bdee-bdc562cc28e4"
    "Managed HSM Crypto Auditor"                 = "2c18b078-7c48-4d3a-af88-5a3a1b3f82b3"
    "Managed HSM Crypto Service Encryption User" = "33413926-3206-4cdd-b39a-83574fe37a17"
    "Managed HSM Crypto Service Release User"    = "21dbd100-6940-42c2-9190-5d6cb909625c"
    "Managed HSM Backup"                         = "7b127d3c-77bd-4e3e-bbe0-dbb8971fa7f8"
    "Managed HSM Restore"                        = "6efe6056-5259-49d2-8b3d-d3d73544b20b"
  }

  effective_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Managed HSM
###############################################################
resource "azurerm_key_vault_managed_hardware_security_module" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.sku_name
  tenant_id           = local.tenant_id
  admin_object_ids    = var.admin_object_ids

  # Mandatory for a production HSM — irreversible, not caller-tunable.
  purge_protection_enabled   = true
  soft_delete_retention_days = var.soft_delete_retention_days

  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    bypass         = var.network_acls.bypass
    default_action = var.network_acls.default_action
  }

  tags = local.effective_tags

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,23}$", local.name))
      error_message = "Managed HSM name must be 3-24 chars, alphanumeric + hyphens, starting with a letter (got '${local.name}'). Shorten the workload or set an explicit var.name."
    }
  }
}

###############################################################
# LOCAL RBAC — data-plane role assignments (opt-in)
#
# Managed HSM has its OWN local RBAC, separate from Azure RBAC. These
# require the HSM to be ACTIVATED (security domain) — on a fresh HSM they
# fail at create time, so apply them in a second stage. See var.role_assignments.
#
# The role definition data source resolves the built-in role's
# resource_manager_id (also a data-plane read → needs activation).
###############################################################
data "azurerm_key_vault_managed_hardware_security_module_role_definition" "this" {
  for_each = { for k, v in var.role_assignments : k => v if v.role_definition_name != null }

  managed_hsm_id = azurerm_key_vault_managed_hardware_security_module.this.id
  name           = local.mhsm_builtin_role_ids[each.value.role_definition_name]
}

resource "azurerm_key_vault_managed_hardware_security_module_role_assignment" "this" {
  for_each = var.role_assignments

  managed_hsm_id = azurerm_key_vault_managed_hardware_security_module.this.id
  name           = coalesce(each.value.name, uuidv5("url", "${azurerm_key_vault_managed_hardware_security_module.this.id}|${each.key}"))
  scope          = each.value.scope
  principal_id   = each.value.principal_id
  role_definition_id = coalesce(
    each.value.role_definition_id,
    try(data.azurerm_key_vault_managed_hardware_security_module_role_definition.this[each.key].resource_manager_id, null),
  )
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_key_vault_managed_hardware_security_module.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
