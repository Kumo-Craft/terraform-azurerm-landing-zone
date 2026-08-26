###############################################################
# MODULE: PrometheusCollector - Main
# Description: DCR + Associations to send Prometheus metrics
#              from an AKS cluster to an Azure Monitor Workspace
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to ../Naming (F-2)
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
  # Single guarded local — avoids "Invalid index" plan error when var.name is set.
  name = var.name != null ? var.name : module.naming["this"].result.monitor_data_collection_rule.name
}

###############################################################
# RESOURCE: Data Collection Rule — Prometheus Forwarder
###############################################################
resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = local.name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = var.data_collection_endpoint_id
  # F-1: kind must be omitted (null) for Prometheus forwarder DCRs.
  # "Linux" is for Container Insights agent DCRs only.

  destinations {
    monitor_account {
      monitor_account_id = var.monitor_workspace_id
      name               = "MonitoringAccount"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
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
# RESOURCE: DCE Association — AKS <-> Data Collection Endpoint
# Name MUST be "configurationAccessEndpoint"
###############################################################
resource "azurerm_monitor_data_collection_rule_association" "dce" {
  name                        = "configurationAccessEndpoint"
  target_resource_id          = var.aks_cluster_id
  data_collection_endpoint_id = var.data_collection_endpoint_id
}

###############################################################
# RESOURCE: DCR Association — AKS <-> Data Collection Rule
###############################################################
resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  # Derive DCRA name from local.name (works for both naming paths).
  name                    = "dcra-${local.name}"
  target_resource_id      = var.aks_cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

###############################################################
# RESOURCE: Management Lock (optional) — F-3
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_data_collection_rule.prometheus.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
