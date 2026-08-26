###############################################################
# MODULE: ManagedHsmStack - Main
# Description: Composes Managed HSM + Private Endpoint via the
#              canonical sibling modules (../ManagedHsm and
#              ../PrivateEndpoint). Batteries-included counterpart
#              to the ../ManagedHsm leaf — mirror of KeyVaultStack.
#              The caller provides the Resource Group via
#              var.resource_group_name (repo convention).
#
# New module — no `moved`/`removed` state migration needed.
###############################################################

resource "time_static" "time" {}

locals {
  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # PE name derived from the HSM name computed by the leaf → pep-mhsm-...
  pe_name = "pep-${module.hsm.name}"
}

###############################################################
# COMPOSED: Managed HSM (../ManagedHsm)
# Naming components + optional name override are forwarded; the leaf
# derives the name and owns all HSM validation + secure defaults
# (purge protection forced true, deny-by-default ACLs, etc.).
###############################################################
module "hsm" {
  source = "../ManagedHsm"

  name                 = var.name
  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload

  location            = var.location
  resource_group_name = var.resource_group_name

  admin_object_ids = var.admin_object_ids
  tenant_id        = var.tenant_id
  sku_name         = var.sku_name

  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = var.public_network_access_enabled
  network_acls                  = var.network_acls

  role_assignments = var.role_assignments

  lock = var.lock
  tags = local.common_tags
}

###############################################################
# COMPOSED: Backup identity (../ManagedIdentity) — opt-in
# UAMI for Managed HSM full backup/restore. Granted Storage Blob Data
# Contributor on the backup storage when backup_storage_scope_id is set.
# The UAMI must still be associated to the HSM out-of-band
# (az keyvault update-hsm --mi-user-assigned <id>) — no azurerm identity block.
###############################################################
module "backup_identity" {
  source = "../ManagedIdentity"
  count  = var.enable_backup_identity ? 1 : 0

  name                = coalesce(var.backup_identity_name, "id-${module.hsm.name}-backup")
  location            = var.location
  resource_group_name = var.resource_group_name

  role_assignments = var.backup_storage_scope_id != null ? {
    backup_blob = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      scope                      = var.backup_storage_scope_id
      description                = "Managed HSM backup UAMI — write encrypted backups to the container."
    }
  } : {}

  tags = local.common_tags
}

###############################################################
# COMPOSED: Private Endpoint (../PrivateEndpoint)
# Single-entry "this" of the canonical PE module's map input.
# Managed HSM private-link sub-resource is `managedhsm`
# (DNS zone privatelink.managedhsm.azure.net).
###############################################################
module "pe" {
  source = "../PrivateEndpoint"

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_endpoints = {
    this = {
      name                          = local.pe_name
      resource_id                   = module.hsm.id
      subresource_names             = ["managedhsm"]
      is_manual_connection          = false
      private_ip_address            = var.pe_private_ip_address
      custom_network_interface_name = var.pe_custom_network_interface_name
      private_dns_zone_group = var.private_dns_zone_ids != null ? {
        name                 = "default"
        private_dns_zone_ids = var.private_dns_zone_ids
      } : null
    }
  }

  tags = local.common_tags
}
