###############################################################
# MODULE: LogAnalyticsWorkspace - Main
# Description: Canonical Azure Log Analytics Workspace leaf +
#              optional Resource Lock.
#
# Secure-by-default (house convention diverges from Azure defaults,
# which are all `true`): local (workspace-key) auth OFF → Entra ID
# only; public ingestion/query OFF → reach it privately via an Azure
# Monitor Private Link Scope (AMPLS). allow_resource_only_permissions
# stays ON (resource-context RBAC).
#
# Out of scope (compose separately): AMPLS wiring, table-level RBAC /
# retention (azurerm_log_analytics_workspace_table), dedicated cluster
# + CMK, solutions, DCR associations.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming — delegated to ../Naming (upstream Azure/naming slug: log).
# Convention: log-{acr}-{env}-{region}-{workload}
# The for_each guard keeps the module out of the graph when var.name
# is set (escape hatch — e.g. callers preserving a `law-` prefix).
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
  name = var.name != null ? var.name : module.naming["this"].result.log_analytics_workspace.name

  effective_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Log Analytics Workspace
###############################################################
resource "azurerm_log_analytics_workspace" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku                                = var.sku
  retention_in_days                  = var.retention_in_days
  daily_quota_gb                     = var.daily_quota_gb
  reservation_capacity_in_gb_per_day = var.reservation_capacity_in_gb_per_day

  # Secure-by-default — see variables.tf.
  local_authentication_enabled    = var.local_authentication_enabled
  internet_ingestion_enabled      = var.internet_ingestion_enabled
  internet_query_enabled          = var.internet_query_enabled
  allow_resource_only_permissions = var.allow_resource_only_permissions

  cmk_for_query_forced                    = var.cmk_for_query_forced
  data_collection_rule_id                 = var.data_collection_rule_id
  immediate_data_purge_on_30_days_enabled = var.immediate_data_purge_on_30_days_enabled

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type = identity.value.type
      # null (not []) when unset — the provider rejects identity_ids on SystemAssigned.
      identity_ids = length(identity.value.identity_ids) > 0 ? identity.value.identity_ids : null
    }
  }

  tags = local.effective_tags
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_log_analytics_workspace.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
