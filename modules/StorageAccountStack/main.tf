###############################################################
# MODULE: StorageAccountStack - Main
# Description: Composes Storage Account + Private Endpoint(s) via
#              the canonical sibling modules (../StorageAccount and
#              ../PrivateEndpoint), mirroring KeyVaultStack. The
#              Resource Group is caller-provided.
#
# One Private Endpoint is created per Storage sub-resource entry in
# var.private_endpoints; each targets a single sub-resource
# (blob/file/queue/table/web/dfs) as Azure requires.
###############################################################

resource "time_static" "time" {}

locals {
  prefix = "${var.subscription_acronym}-${var.environment}-${var.region_code}"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# COMPOSED: Storage Account
# Naming is delegated to the canonical StorageAccount module's own
# Naming submodule — we forward the naming components (and an
# optional explicit `name` override).
###############################################################
module "storage" {
  source = "../StorageAccount"

  name                 = var.name
  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload

  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  account_kind             = var.account_kind

  public_network_access_enabled     = var.public_network_access_enabled
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = var.default_to_oauth_authentication
  cross_tenant_replication_enabled  = var.cross_tenant_replication_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  local_user_enabled                = var.local_user_enabled

  customer_managed_key = var.customer_managed_key
  identity_type        = var.identity_type
  identity_ids         = var.identity_ids

  blob_delete_retention_days      = var.blob_delete_retention_days
  container_delete_retention_days = var.container_delete_retention_days
  blob_versioning_enabled         = var.blob_versioning_enabled
  blob_change_feed_enabled        = var.blob_change_feed_enabled
  blob_last_access_time_enabled   = var.blob_last_access_time_enabled

  containers                 = var.containers
  file_shares                = var.file_shares
  azure_files_authentication = var.azure_files_authentication
  network_rules              = var.network_rules
  sas_policy                 = var.sas_policy

  role_assignments = var.role_assignments
  lock             = var.lock

  tags = local.common_tags
}

###############################################################
# COMPOSED: Private Endpoint(s)
# One canonical PrivateEndpoint module instance per sub-resource.
###############################################################
module "pe" {
  source   = "../PrivateEndpoint"
  for_each = var.private_endpoints

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = local.common_tags

  private_endpoints = {
    this = {
      name                          = "pep-${local.prefix}-st-${var.workload}-${each.key}"
      resource_id                   = module.storage.id
      subresource_names             = [each.key]
      is_manual_connection          = false
      private_ip_address            = each.value.private_ip_address
      custom_network_interface_name = each.value.custom_network_interface_name
      private_dns_zone_group = each.value.private_dns_zone_ids != null ? {
        name                 = "default"
        private_dns_zone_ids = each.value.private_dns_zone_ids
      } : null
      # `TargetResource` and `SubresourceType` are stamped by the
      # PrivateEndpoint module itself — no need to duplicate here.
    }
  }
}
