###############################################################
# MODULE: ContainerInsightsCollector - Main
#
# DCR + DCRA pair shipping Container Insights streams from an AKS
# cluster to a Log Analytics Workspace via the ama-logs agent (the
# oms_agent addon, enabled separately on the cluster).
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to ../Naming (F-1)
# Azure/naming/azurerm v0.4.3 exposes monitor_data_collection_rule.
# module.naming["this"] is only instantiated when var.name == null.
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
  # F-1: Single guarded local — avoids "Invalid index" plan error when var.name is set.
  name = var.name != null ? var.name : module.naming["this"].result.monitor_data_collection_rule.name

  # Container Insights destination name — referenced by data_flow.destinations.
  destination_name = "ciworkspace"

  # extension_json carries the ama-logs configuration (data collection
  # settings). Serialised here so callers don't have to fiddle with JSON.
  extension_json = jsonencode({
    dataCollectionSettings = {
      interval               = var.data_collection_settings.interval
      namespaceFilteringMode = var.data_collection_settings.namespace_filter_mode
      namespaces             = var.data_collection_settings.namespaces
      enableContainerLogV2   = var.data_collection_settings.enable_container_log_v2
    }
  })
}

###############################################################
# Data Collection Rule — Container Insights
###############################################################
resource "azurerm_monitor_data_collection_rule" "ci" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = local.destination_name
    }
  }

  data_flow {
    streams      = var.streams
    destinations = [local.destination_name]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = var.streams
      extension_json = local.extension_json
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# DCR Association — AKS cluster <-> DCR
#
# Unlike Managed Prometheus, Container Insights via LAW does NOT
# need a separate DCE association — the ama-logs agent talks
# directly to the LAW ingestion endpoint.
###############################################################
resource "azurerm_monitor_data_collection_rule_association" "ci" {
  # F-2: Derive DCRA name from local.name (works for both naming paths).
  name                    = "dcra-${local.name}"
  target_resource_id      = var.aks_cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.ci.id
  description             = "Container Insights — AKS cluster to LAW."
}

###############################################################
# RESOURCE: Management Lock (optional) — F-3
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_data_collection_rule.ci.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment (F-4)
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = azurerm_monitor_data_collection_rule.ci.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}
