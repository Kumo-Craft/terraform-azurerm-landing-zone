###############################################################
# MODULE: StorageAccount - Main
# Description: Azure Storage Account with lock and RBAC
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule
# (wrapper around Azure/naming/azurerm).
#
# Convention (unchanged from previous implementation):
#   st{subscription_acronym}{environment}{region_code}{workload}
# Example:
#   stapiprodgwcblob01
#
# Note: the upstream Azure/naming/azurerm module enforces the
# Storage Account constraints natively (lowercase alphanumeric
# only, 3-24 chars, no hyphens) — no manual char-stripping needed.
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
  name                               = var.name != null ? var.name : module.naming["this"].result.storage_account.name
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"

  # Merge caller-supplied identity_ids (set) with the CMK UAMI (deduplicated).
  # The customer_managed_key block requires its UAMI to also be referenced
  # in the identity block — this is enforced automatically here.
  cmk_identity_ids = var.customer_managed_key != null ? toset([var.customer_managed_key.user_assigned_identity_id]) : toset([])
  all_identity_ids = tolist(setunion(var.identity_ids, local.cmk_identity_ids))

  # The Queue service only exists for General-purpose accounts (Standard tier,
  # kind Storage or StorageV2). Premium, FileStorage, BlockBlobStorage and
  # BlobStorage accounts expose no queue endpoint, so queue_properties cannot be
  # set on them (provider/Azure API constraint). Queue Analytics logging
  # (CKV_AZURE_33) is therefore only applicable — and enabled by default — for
  # queue-capable accounts.
  queue_service_supported = var.account_tier == "Standard" && contains(["Storage", "StorageV2"], var.account_kind)
  queue_logging_enabled   = local.queue_service_supported && var.queue_logging_enabled
}

###############################################################
# RESOURCE: Storage Account
###############################################################
resource "azurerm_storage_account" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  account_kind             = var.account_kind

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = var.public_network_access_enabled
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = var.default_to_oauth_authentication
  cross_tenant_replication_enabled  = var.cross_tenant_replication_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  local_user_enabled                = var.local_user_enabled
  allow_nested_items_to_be_public   = false

  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type         = var.identity_type
      identity_ids = length(local.all_identity_ids) > 0 ? local.all_identity_ids : null
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key != null ? [var.customer_managed_key] : []
    content {
      key_vault_key_id          = customer_managed_key.value.key_vault_key_id
      user_assigned_identity_id = customer_managed_key.value.user_assigned_identity_id
    }
  }

  dynamic "blob_properties" {
    # FileStorage (Premium Azure Files) doesn't support blob_properties
    for_each = var.account_kind != "FileStorage" ? [1] : []
    content {
      versioning_enabled       = var.blob_versioning_enabled
      change_feed_enabled      = var.blob_change_feed_enabled
      last_access_time_enabled = var.blob_last_access_time_enabled

      delete_retention_policy {
        days = var.blob_delete_retention_days
      }
      container_delete_retention_policy {
        days = var.container_delete_retention_days
      }
    }
  }

  # Storage Analytics logging for the Queue service (read/write/delete).
  # Secure-by-default (CKV_AZURE_33). Only emitted for queue-capable accounts
  # (Standard tier + Storage/StorageV2 kind); silently skipped otherwise since
  # the queue endpoint does not exist there.
  dynamic "queue_properties" {
    for_each = local.queue_logging_enabled ? [1] : []
    content {
      logging {
        version               = "1.0"
        read                  = true
        write                 = true
        delete                = true
        retention_policy_days = var.queue_logging_retention_days
      }
    }
  }

  dynamic "azure_files_authentication" {
    for_each = var.azure_files_authentication != null ? [var.azure_files_authentication] : []
    content {
      directory_type                 = azure_files_authentication.value.directory_type
      default_share_level_permission = azure_files_authentication.value.default_share_level_permission

      dynamic "active_directory" {
        for_each = azure_files_authentication.value.active_directory != null ? [azure_files_authentication.value.active_directory] : []
        content {
          domain_guid         = active_directory.value.domain_guid
          domain_name         = active_directory.value.domain_name
          domain_sid          = active_directory.value.domain_sid
          forest_name         = active_directory.value.forest_name
          netbios_domain_name = active_directory.value.netbios_domain_name
          storage_sid         = active_directory.value.storage_sid
        }
      }
    }
  }

  dynamic "network_rules" {
    for_each = var.network_rules != null ? [var.network_rules] : []
    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
      ip_rules                   = network_rules.value.ip_rules
    }
  }

  dynamic "sas_policy" {
    for_each = var.sas_policy != null ? [var.sas_policy] : []
    content {
      expiration_period = sas_policy.value.expiration_period
      expiration_action = sas_policy.value.expiration_action
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # SA destruction = data loss with soft-delete grace window only. State backends
  # + data lakes + diag-target SAs cascade application + monitoring + audit loss.
  # Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Storage Containers
###############################################################
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value.name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = each.value.access_type
}

###############################################################
# RESOURCE: File Shares (Azure Files)
###############################################################
resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = each.value.name
  storage_account_id = azurerm_storage_account.this.id
  quota              = each.value.quota_gb
  access_tier        = each.value.access_tier
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_storage_account.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
# Each entry in var.role_assignments instantiates one canonical
# RoleAssignment module call. Sprint 7 P0 #1 reversed: now that
# RoleAssignment exists and is ✅ PASS, composition replaces the
# inline duplication.
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = azurerm_storage_account.this.id
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
