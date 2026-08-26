###############################################################
# MODULE: KeyVaultStack - Main
# Description: Composes Key Vault + Private Endpoint via the
#              canonical sibling modules (../KeyVault and
#              ../PrivateEndpoint). The caller provides the
#              Resource Group via var.resource_group_name — same
#              convention as every other leaf module in the repo
#              since v0.2.1 (NetworkWatcher RG removal).
#
# Sprint 8 cleanup. Removes the inline azurerm_key_vault and
# azurerm_private_endpoint blocks previously flagged by the
# drift-check script. Also drops the conditional RG creation
# (var.create_resource_group + var.resource_group_workload) and
# the RG-level lock + role_assignments inputs — those are now the
# caller's responsibility (the LZ Terragrunt typically wires a
# canonical ResourceGroup module ahead of this Stack).
#
# State migration via `moved` blocks (for the resources that
# stayed inside the module) + `removed { lifecycle { destroy =
# false } }` blocks (for resources that left the module entirely).
#
# Callers that previously had `create_resource_group = true` on
# their KVStack instance MUST add the following block in their
# Terragrunt root config (apply ONCE then delete):
#
#   removed { from = module.kvstack.azurerm_resource_group.this;     lifecycle { destroy = false } }
#   removed { from = module.kvstack.module.lock;                     lifecycle { destroy = false } }
#   removed { from = module.kvstack.module.rg_role_assignments;      lifecycle { destroy = false } }
#
# The three `removed` blocks tell Terraform: "these are gone from
# the module config but DO NOT destroy them in Azure". The
# downstream consumer is now expected to wire the RG, its lock,
# and its role assignments via a `../ResourceGroup` module
# instance (which handles all three through its per-entry shape).
#
# Callers that already used `create_resource_group = false` (i.e.
# already passed in `resource_group_name` from elsewhere) are
# unaffected — only the per-Stack lock + role_assignments blocks
# at the RG scope might still be in their state if they had those
# set on the OLD Stack, but typically they didn't.
#
# See README.md "Breaking changes" for the full migration recipe.
###############################################################

data "azurerm_client_config" "current" {}

resource "time_static" "time" {}

locals {
  prefix = "${var.subscription_acronym}-${var.environment}-${var.region_code}"

  kv_suffix = var.kv_suffix != null ? var.kv_suffix : var.workload

  kv_name = var.kv_name != null ? var.kv_name : "kv-${local.prefix}-${local.kv_suffix}"
  pe_name = "pep-${local.prefix}-kv-${local.kv_suffix}"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# COMPOSED: Key Vault
# Uses the legacy `name` escape hatch on the canonical KeyVault —
# we pass local.kv_name explicitly so the canonical Naming
# submodule is bypassed and the byte-for-byte historic KV name
# is preserved.
#
# The deployer RBAC (assign_rbac_to_current_user) and the Entra
# admin group are forwarded into the canonical KV's own inputs
# rather than re-implemented at the Stack level.
###############################################################
module "kv" {
  source = "../KeyVault"

  name                = local.kv_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
  sku_name            = var.sku_name

  enable_rbac = var.enable_rbac

  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_template_deployment = var.enabled_for_template_deployment

  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  public_network_access_enabled = var.public_network_access_enabled

  network_acls = var.network_acls

  assign_rbac_to_current_user = var.assign_rbac_to_current_user

  role_assignments = var.kv_admin_group_object_id != null ? {
    admin_group = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = var.kv_admin_group_object_id
      principal_type             = "Group"
    }
  } : {}

  tags = local.common_tags
}

moved {
  from = azurerm_key_vault.this
  to   = module.kv.azurerm_key_vault.this
}

# NOTE: the deployer role assignment is intentionally NOT migrated here. As of
# v0.2.82 the canonical KeyVault module owns that relocation internally
# (azurerm_role_assignment.deployer -> module.deployer_rbac[0]...), which also
# covers KeyVaultStack consumers through module.kv. Re-declaring it at this
# layer collided with that block ("Ambiguous move statements" — both targeted
# module.kv.module.deployer_rbac[0].azurerm_role_assignment.this). Pre-Sprint-8
# consumers still carrying module.kv_admin[0] in state run a one-time:
#   terraform state mv 'module.kv_admin[0].azurerm_role_assignment.this' \
#     'module.kv.module.deployer_rbac[0].azurerm_role_assignment.this'

moved {
  from = module.kv_admin_group[0].azurerm_role_assignment.this
  to   = module.kv.module.role_assignments["admin_group"].azurerm_role_assignment.this
}

###############################################################
# COMPOSED: Private Endpoint
# Single-entry "this" of the canonical PE module's map input.
###############################################################
module "pe" {
  source = "../PrivateEndpoint"

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_endpoints = {
    this = {
      name                          = local.pe_name
      resource_id                   = module.kv.id
      subresource_names             = ["vault"]
      is_manual_connection          = false
      private_ip_address            = var.pe_private_ip_address
      custom_network_interface_name = var.pe_custom_network_interface_name
      private_dns_zone_group = var.private_dns_zone_ids != null ? {
        name                 = "default"
        private_dns_zone_ids = var.private_dns_zone_ids
      } : null
      # `TargetResource` and `SubresourceType` are stamped by the
      # PrivateEndpoint module itself — no need to duplicate here.
    }
  }

  tags = local.common_tags
}

moved {
  from = azurerm_private_endpoint.this
  to   = module.pe.azurerm_private_endpoint.this["this"]
}
