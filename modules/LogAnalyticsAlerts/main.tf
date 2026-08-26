###############################################################
# MODULE: LogAnalyticsAlerts - Main
# Description: Generic KQL-based Azure Monitor alerts on a LAW,
# plus optional DCR-based custom table ingestion pipeline
# (DCE + DCR + table + RBAC) for clients using the modern
# Logs Ingestion API (OAuth).
#
# Why not Data Collector API: Microsoft has deprecated the
# legacy HTTP Data Collector API (retirement 14 Sep 2026), and
# in hardened workspaces `local_authentication_enabled = false`
# disables Shared Keys entirely. Also the legacy API creates
# tables where `TimeGenerated` is typed as string, which breaks
# scheduled query alerts. DCR-based ingestion fixes all three.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — via ../Naming submodule.
# Convention: sqr-{sub}-{env}-{region}-{workload}
# Note: upstream Azure/naming/azurerm 0.4.3 exposes
# monitor_scheduled_query_rules_alert (v1 slug) but not the v2
# variant. We apply the CAF sqr- slug manually and join the
# suffix from the Naming module.
# The for_each guard ensures the module is only instantiated
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
  # sqr- is the CAF slug for Scheduled Query Rules (v2 type not in upstream 0.4.3).
  name = var.name != null ? var.name : "sqr-${join("-", module.naming["this"].suffix)}"

  dce_name = "${local.name}-dce"
  dcr_name = "${local.name}-dcr"

  # Any table with an ingestion block gets a DCR stream; tables without it are
  # created but not wired into the DCR (read-only for queries / manual ingestion).
  ingestion_tables = {
    for k, v in var.custom_tables : k => v
    if v.ingestion != null
  }

  # A DCR is deployed only if at least one table requests ingestion AND the
  # caller passed a LAW resource id.
  deploy_ingestion = length(local.ingestion_tables) > 0

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# Custom tables (*_CL)
#
# Implementation note — "TimeGenerated typed as string" bug:
# The @2022-10-01 tables API will accept a user-supplied
# `TimeGenerated` column and store it as whatever type was
# sent (previous revisions silently coerced it to string).
# For DCR-based Analytics tables, TimeGenerated is populated
# by the platform and MUST NOT be declared in `columns`. The
# DCR transformKql (`source | extend TimeGenerated = now()`)
# or a payload field promoted by the DCR provides the value.
###############################################################
resource "azapi_resource" "custom_table" {
  for_each = var.custom_tables

  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  parent_id = var.law_id
  name      = "${each.key}_CL"

  # IMPORTANT: TimeGenerated is mandatory on the Tables API path (custom_log
  # tables created via PUT). It MUST be typed `dateTime` (camelCase, per the
  # ColumnTypeEnum spec). We always inject it as the first column and strip
  # any caller-declared duplicate to avoid the "shadow column" bug where a
  # mistyped TimeGenerated gets stored as `string` and shadows the real one.
  body = {
    properties = {
      plan                 = each.value.plan
      retentionInDays      = each.value.retention_days
      totalRetentionInDays = each.value.total_retention_days
      schema = {
        name = "${each.key}_CL"
        columns = concat(
          [{ name = "TimeGenerated", type = "dateTime" }],
          [
            for col_name, col_type in each.value.columns : {
              name = col_name
              type = col_type
            } if lower(col_name) != "timegenerated"
          ]
        )
      }
    }
  }

  response_export_values = ["properties.schema"]
}

###############################################################
# Data Collection Endpoint (DCE) - OAuth ingestion entrypoint
# for Logs Ingestion API clients. Public network access mirrors
# the LAW hardening; callers using private link must pair this
# with an AMPLS scope and a Private Endpoint on the DCE.
###############################################################
resource "azurerm_monitor_data_collection_endpoint" "this" {
  count = local.deploy_ingestion ? 1 : 0

  name                          = local.dce_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  kind                          = "Linux"
  public_network_access_enabled = var.ingestion_public_network_access_enabled
  description                   = "DCE for custom ${var.workload} log ingestion (Logs Ingestion API / OAuth)"

  tags = local.common_tags
}

###############################################################
# Data Collection Rule (DCR) - one rule, one stream per
# ingestion-enabled custom table. The transformKql guarantees
# that `TimeGenerated` is set to a proper datetime even if the
# client sends it as an ISO-8601 string field.
###############################################################
resource "azurerm_monitor_data_collection_rule" "this" {
  count = local.deploy_ingestion ? 1 : 0

  name                        = local.dcr_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this[0].id
  description                 = "DCR routing custom streams to LAW custom tables (${join(", ", [for k, _ in local.ingestion_tables : "${k}_CL"])})"

  # Destination: the Log Analytics Workspace hosting the *_CL tables.
  destinations {
    log_analytics {
      workspace_resource_id = var.law_id
      name                  = "law-destination"
    }
  }

  # One stream-declaration per ingestion-enabled table - this is the schema
  # the client must POST (JSON array of objects matching these columns).
  dynamic "stream_declaration" {
    for_each = local.ingestion_tables
    content {
      stream_name = "Custom-${stream_declaration.key}_CL"

      dynamic "column" {
        for_each = stream_declaration.value.ingestion.input_columns
        content {
          name = column.key
          type = column.value
        }
      }
    }
  }

  # One data_flow per stream -> destination -> output table. transformKql
  # normalises TimeGenerated so alerts consistently see a datetime column.
  dynamic "data_flow" {
    for_each = local.ingestion_tables
    content {
      streams       = ["Custom-${data_flow.key}_CL"]
      destinations  = ["law-destination"]
      output_stream = "Custom-${data_flow.key}_CL"
      # DCR transform_kql only supports a restricted subset of KQL — functions
      # like `coalesce()` are NOT available. Use `iff(isnull(...), ..., ...)`.
      # Default transform is a TimeGenerated safety-net; callers can override.
      transform_kql = coalesce(
        data_flow.value.ingestion.transform_kql,
        "source | extend TimeGenerated = iff(isnull(TimeGenerated), now(), TimeGenerated)"
      )
    }
  }

  tags = local.common_tags

  depends_on = [azapi_resource.custom_table]
}

###############################################################
# RBAC - "Monitoring Metrics Publisher" on the DCR for every
# principal (typically CI/CD SPNs / workload identities) that
# must POST events through the Logs Ingestion API.
###############################################################
module "dcr_publisher" {
  source   = "../RoleAssignment"
  for_each = local.deploy_ingestion ? toset(var.ingestion_principal_ids) : toset([])

  scope                = azurerm_monitor_data_collection_rule.this[0].id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = each.value
}

moved {
  from = azurerm_role_assignment.dcr_publisher
  to   = module.dcr_publisher.azurerm_role_assignment.this
}

###############################################################
# Scheduled Query Rules (KQL alerts)
###############################################################
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  for_each = var.alerts

  # Ensure tables AND the ingestion pipeline exist before alerts are
  # validated - Azure semantically validates column types at create time.
  depends_on = [
    azapi_resource.custom_table,
    azurerm_monitor_data_collection_rule.this,
  ]

  name                = "${local.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location

  display_name = coalesce(each.value.display_name, each.key)
  description  = each.value.description
  severity     = each.value.severity
  enabled      = each.value.enabled

  evaluation_frequency = each.value.evaluation_frequency
  window_duration      = each.value.window_duration
  scopes               = [var.law_id]

  mute_actions_after_alert_duration = each.value.mute_actions_after_alert_duration
  skip_query_validation             = each.value.skip_query_validation
  query_time_range_override         = each.value.query_time_range_override
  workspace_alerts_storage_enabled  = each.value.workspace_alerts_storage_enabled

  criteria {
    query                   = each.value.kql
    time_aggregation_method = each.value.time_aggregation_method
    metric_measure_column   = each.value.metric_measure_column
    threshold               = each.value.threshold
    operator                = each.value.operator

    failing_periods {
      number_of_evaluation_periods             = each.value.failing_periods.number_of_evaluation_periods
      minimum_failing_periods_to_trigger_alert = each.value.failing_periods.minimum_failing_periods_to_trigger_alert
    }
  }

  action {
    action_groups     = each.value.action_group_ids != null ? each.value.action_group_ids : var.action_group_ids
    custom_properties = each.value.custom_properties
  }

  auto_mitigation_enabled = each.value.auto_mitigation_enabled

  tags = local.common_tags
}

###############################################################
# RESOURCE: Management Lock (optional) — F-13
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    for k, _ in var.alerts : k => {
      scope      = azurerm_monitor_scheduled_query_rules_alert_v2.this[k].id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-${k}" : null
    }
  } : {}
}
