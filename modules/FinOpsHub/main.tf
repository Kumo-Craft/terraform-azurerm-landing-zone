###############################################################
# Module FinOpsHub
###############################################################
# Deploys the Microsoft FinOps Toolkit Hub infrastructure:
# ADLS Gen2 Storage, Azure Data Explorer, Data Factory,
# Event Grid, and RBAC assignments.
# The caller provides the resource group (compose with
# ../ResourceGroup at root — see README Breaking changes v0.2.49).
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — via ../Naming submodule (F-4).
# Convention: {type}-{acr}-{env}-{region}-{workload}
# Storage account (st) and ADX (adx) types are not natively
# exposed by Azure/naming/azurerm 0.4.3, so we build names
# inline using the suffix list + literal slugs to preserve
# existing state addresses (no state migration needed).
# ADF uses adf- prefix from upstream; Event Grid uses evgt-.
# The for_each guard ensures Naming is only instantiated
# when var.name is null — avoids "Invalid index" in plan-time tests.
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
  # Single guarded local — module.naming["this"] only exists when var.name == null.
  # Collapse naming into one inline ternary to avoid "Invalid index" in plan-time tests.
  suffix_str = var.name == null ? join("-", module.naming["this"].suffix) : null

  # Storage account: stfh{acr}{env}{region}01 — no hyphens (Storage char rules).
  # Preserve existing slug prefix "stfh" to avoid state migration.
  st_name = var.name != null ? "stfh${var.name}" : "stfh${var.subscription_acronym}${var.environment}${var.region_code}01"

  # ADX cluster: adxfh{acr}{env}{region}01 — no hyphens (Kusto char rules).
  # Preserve existing slug prefix "adxfh" to avoid state migration.
  adx_name = var.name != null ? "adxfh${var.name}" : "adxfh${var.subscription_acronym}${var.environment}${var.region_code}01"

  # ADF / EventGrid / EventHub — standard hyphenated convention.
  adf_name   = var.name != null ? "adf-${var.name}" : "adf-${local.suffix_str}"
  evgt_name  = var.name != null ? "evgt-${var.name}" : "evgt-${local.suffix_str}"
  evhns_name = var.name != null ? "evhns-${var.name}" : "evhns-${local.suffix_str}"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  containers = toset(["msexports", "ingestion", "config"])
}

###############################################################
# TOMBSTONE — F-1 BREAKING (v0.2.49)
# Inline azurerm_resource_group.this removed. Callers must
# compose ../ResourceGroup at root and pass resource_group_name.
# This block prevents Terraform from trying to destroy the Azure
# RG if the caller has not yet done a state mv.
# See README.md "Breaking changes (v0.2.49)" for the migration recipe.
###############################################################
removed {
  from = azurerm_resource_group.this
  lifecycle { destroy = false }
}

###############################################################
# Storage Account — ADLS Gen2
###############################################################
resource "azurerm_storage_account" "this" {
  name                            = local.st_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  is_hns_enabled                  = true
  public_network_access_enabled   = var.enable_public_access
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  # CKV_AZURE_244 — disable SFTP/local-user (shared-key-style) auth. FinOps data
  # access is via Entra ID + managed identities (ADF, ADX, Cost Management SP)
  # only, so local users are never needed. Secure-by-default; in-place update.
  local_user_enabled = false
  tags               = local.common_tags

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # FinOps SA destruction = loss of MS Cost Management Exports history + ADF
  # ingestion settings + ADX raw blobs. Soft-delete grace only. Disabling
  # requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# Containers: msexports, ingestion, config
###############################################################
resource "azurerm_storage_container" "this" {
  for_each = local.containers

  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
}

###############################################################
# settings.json — Hub configuration
###############################################################
resource "azurerm_storage_blob" "settings" {
  name                   = "settings.json"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.this["config"].name
  type                   = "Block"
  content_type           = "application/json"

  source_content = jsonencode({
    type      = "hub"
    version   = "0.12"
    learnMore = "https://aka.ms/finops/hubs"
    retention = {
      msexports = { days = var.export_retention_days }
      ingestion = { months = var.ingestion_retention_months }
    }
    scopes = []
  })
}

###############################################################
# Lifecycle policy — auto-cleanup of exports
###############################################################
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.export_retention_days > 0 ? [1] : []
    content {
      name    = "cleanup-msexports"
      enabled = true
      filters {
        prefix_match = ["msexports/"]
        blob_types   = ["blockBlob"]
      }
      actions {
        base_blob {
          delete_after_days_since_creation_greater_than = var.export_retention_days
        }
      }
    }
  }

  rule {
    name    = "cleanup-ingestion"
    enabled = true
    filters {
      prefix_match = ["ingestion/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.ingestion_retention_months * 31
      }
    }
  }
}
