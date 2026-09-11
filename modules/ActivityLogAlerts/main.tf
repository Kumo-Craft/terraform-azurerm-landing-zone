###############################################################
# MODULE: ActivityLogAlerts - Main
# Description: Map-driven Azure Monitor activity-log alerts
#              (azurerm_monitor_activity_log_alert) on a subscription.
#              First use case: Service Health (incidents, planned
#              maintenance, service deprecations) — Azure Advisor flags
#              its absence as High.
#
# Modeled on ../LogAnalyticsAlerts (map var.alerts, name {base}-{key}).
#
# ⚠️ location is HARDCODED "global". The provider requires location and Azure
# accepts only { global, westeurope, northeurope, eastus2euap } for this type —
# NOT the caller's region (a "germanywestcentral" passes plan, fails apply).
# Service Health alert rules specifically MUST be "global", so this module
# standardizes on "global" and does not expose location. (westeurope/northeurope
# are EU-Data-Boundary processing options for non-ServiceHealth categories — a
# possible future opt-in, deliberately out of scope here.)
###############################################################

resource "time_static" "time" {} # stable CreatedOn timestamp

###############################################################
# Naming Convention — house prefix `ala-` + the Naming submodule's
# suffix (Azure/naming 0.4.3 has no slug for this type — same manual
# approach as LogAnalyticsAlerts' `sqr-`).
# Base:  ala-{subscription_acronym}-{environment}-{region_code}-{workload}
# Alert: {base}-{key}  e.g. ala-pgs-prod-gwc-servicehealth-incidents
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
  base_name = var.name != null ? var.name : "ala-${join("-", module.naming["this"].suffix)}"

  # House convention: stamp a stable CreatedOn tag (same pattern as
  # LogAnalyticsAlerts and the rest of the repo).
  common_tags = merge(
    var.tags,
    { CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h")) }
  )
}

###############################################################
# RESOURCE: Activity Log Alerts
###############################################################
resource "azurerm_monitor_activity_log_alert" "this" {
  for_each = var.alerts

  name                = "${local.base_name}-${each.key}"
  resource_group_name = var.resource_group_name

  # GLOBAL resource — do not parameterise (see module header).
  location = "global"

  scopes      = var.scopes
  description = each.value.description
  enabled     = each.value.enabled

  criteria {
    category = each.value.category

    dynamic "service_health" {
      for_each = each.value.service_health != null ? [each.value.service_health] : []
      content {
        events    = service_health.value.events
        locations = service_health.value.locations
        services  = service_health.value.services
      }
    }

    dynamic "resource_health" {
      for_each = each.value.resource_health != null ? [each.value.resource_health] : []
      content {
        current  = resource_health.value.current
        previous = resource_health.value.previous
        reason   = resource_health.value.reason
      }
    }
  }

  # Same action group set on every alert.
  dynamic "action" {
    for_each = toset(var.action_group_ids)
    content {
      action_group_id = action.value
    }
  }

  tags = local.common_tags
}

###############################################################
# RESOURCE: Management Lock (optional, per alert)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    for k, _ in var.alerts : k => {
      scope      = azurerm_monitor_activity_log_alert.this[k].id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-${k}" : null
    }
  } : {}
}
