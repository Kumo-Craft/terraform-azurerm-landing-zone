###############################################################
# MODULE: AvdInsightsCollector - Main
#
# DCR + DCRA set feeding Azure Virtual Desktop Insights: ships the
# performance counters and Windows event logs the AVD Insights workbook
# reads from the session hosts to a Log Analytics Workspace via AMA.
#
# The workspace is an INPUT (compose ../LogAnalyticsWorkspace) — never
# created here. Sibling of ../ContainerInsightsCollector.
#
# Streams are Microsoft-Perf + Microsoft-Event on purpose: the AVD
# Insights workbook reads the Perf and Event tables. NOT
# Microsoft-InsightsMetrics — that feeds VM Insights, isn't read by AVD
# Insights, and would force sampling_frequency_in_seconds = 60.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming — delegated to ../Naming. extra_suffix appends the component,
# giving dcr-{acr}-{env}-{region}-{workload}-avdinsights (same shape as
# AlzManagement's dcr-mgm-prod-gwc-01-vminsights).
# The for_each guard keeps the module out of the graph when var.name is set.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
  extra_suffix         = ["avdinsights"]
}

locals {
  name = var.name != null ? var.name : module.naming["this"].result.monitor_data_collection_rule.name

  # Destination name — referenced by every data_flow.destinations.
  destination_name = "avdworkspace"
}

###############################################################
# Data Collection Rule — AVD Insights
###############################################################
resource "azurerm_monitor_data_collection_rule" "avd" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Windows"
  description         = "Azure Virtual Desktop Insights — session host perf counters + event logs to LAW."

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = local.destination_name
    }
  }

  # Perf counters -> Perf table.
  data_flow {
    streams      = ["Microsoft-Perf"]
    destinations = [local.destination_name]
  }

  # Windows event logs -> Event table.
  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = [local.destination_name]
  }

  data_sources {
    dynamic "performance_counter" {
      for_each = var.performance_counters
      content {
        name                          = performance_counter.value.name
        streams                       = ["Microsoft-Perf"]
        sampling_frequency_in_seconds = performance_counter.value.sampling_frequency_in_seconds
        counter_specifiers            = performance_counter.value.counter_specifiers
      }
    }

    dynamic "windows_event_log" {
      for_each = var.windows_event_logs
      content {
        name           = windows_event_log.value.name
        streams        = ["Microsoft-Event"]
        x_path_queries = windows_event_log.value.x_path_queries
      }
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
# DCR Associations — session hosts <-> DCR
#
# Empty by default (var.session_host_ids = []): the DCR is created first,
# the associations land on a later apply once the hosts exist. The DCRA
# name is scoped to its target resource, so the same name across hosts is fine.
###############################################################
resource "azurerm_monitor_data_collection_rule_association" "avd" {
  for_each = toset(var.session_host_ids)

  name                    = "dcra-${local.name}"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.avd.id
  description             = "AVD Insights — session host to LAW."
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_data_collection_rule.avd.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
