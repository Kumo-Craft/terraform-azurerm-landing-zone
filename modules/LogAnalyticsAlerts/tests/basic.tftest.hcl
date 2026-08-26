# Plan-time tests for the LogAnalyticsAlerts module.
#
# Mocks azurerm + time + azapi. Covers:
#   1. happy_default_naming        — convention naming, 1 alert (severity=2, failing 2/3), no DCE/DCR
#   2. happy_name_override         — explicit var.name, assert used + XOR path OK
#   3. happy_with_dce_dcr          — custom_tables with ingestion, DCE + DCR planned
#   4. happy_multi_alerts          — 2 alerts in var.alerts map
#   5. happy_with_lock             — var.lock = CanNotDelete, lock_ids planned
#   6. happy_amw_only_no_dcr       — alerts without custom tables (workspace-only scope)
#   7. validator_severity_out_of_range     — severity = 5 → failure
#   8. validator_failing_periods_cross_var — minimum_failing > number_of_periods → failure
#   9. validator_invalid_law_id            — malformed law_id → regex failure
#  10. validator_invalid_action_group_id   — malformed action_group_id → regex failure
#
# Run with:
#   cd modules/LogAnalyticsAlerts
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}
mock_provider "azapi" {}

# Shared required inputs reused across most runs.
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "monitoring"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-monitoring"
  law_id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
  action_group_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.Insights/actionGroups/ag-mgm-prod-gwc-ops"
  ]
  alerts = {
    high-cpu = {
      display_name         = "High CPU"
      kql                  = "Perf | where CounterName == '% Processor Time' | summarize count() by Computer | where count_ > 0"
      severity             = 2
      evaluation_frequency = "PT5M"
      window_duration      = "PT15M"
      failing_periods = {
        number_of_evaluation_periods             = 3
        minimum_failing_periods_to_trigger_alert = 2
      }
    }
  }
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, no DCE/DCR.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["high-cpu"].resource_group_name == "rg-mgm-prod-gwc-monitoring"
    error_message = "resource_group_name must match the caller-provided value."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["high-cpu"].severity == 2
    error_message = "severity must be 2 as provided."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["high-cpu"].location == "germanywestcentral"
    error_message = "location must match the caller-provided value."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_endpoint.this) == 0
    error_message = "No DCE must be planned when no custom_tables with ingestion are provided."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) == 0
    error_message = "No DCR must be planned when no custom_tables with ingestion are provided."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "sqr-custom-override"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["high-cpu"].name == "sqr-custom-override-high-cpu"
    error_message = "Alert rule name must use the explicit var.name as prefix."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_dce_dcr — ingestion table triggers DCE + DCR.
# -----------------------------------------------------------------------
run "happy_with_dce_dcr" {
  command = plan

  variables {
    custom_tables = {
      AppEvents = {
        columns = {
          EventType = "string"
          Message   = "string"
        }
        ingestion = {
          input_columns = {
            EventType = "string"
            Message   = "string"
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_endpoint.this) == 1
    error_message = "Exactly 1 DCE must be planned when a custom_table has an ingestion block."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) == 1
    error_message = "Exactly 1 DCR must be planned when a custom_table has an ingestion block."
  }

  assert {
    condition     = azurerm_monitor_data_collection_endpoint.this[0].public_network_access_enabled == false
    error_message = "DCE public_network_access_enabled must default to false (CAF secure-by-default)."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_multi_alerts — 2 alerts in var.alerts map.
# -----------------------------------------------------------------------
run "happy_multi_alerts" {
  command = plan

  variables {
    alerts = {
      high-cpu = {
        kql      = "Perf | where CounterName == '% Processor Time' | summarize count() by Computer | where count_ > 0"
        severity = 2
      }
      high-memory = {
        kql      = "Perf | where CounterName == 'Available MBytes' and CounterValue < 512 | summarize count() by Computer"
        severity = 3
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 2
    error_message = "Exactly 2 alert rules must be planned when 2 entries are in var.alerts."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_lock — var.lock = CanNotDelete → lock_ids has entries.
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry (one per alert) when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_amw_only_no_dcr — workspace-only alerts, no ingestion tables.
# -----------------------------------------------------------------------
run "happy_amw_only_no_dcr" {
  command = plan

  variables {
    custom_tables = {}
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_endpoint.this) == 0
    error_message = "No DCE must be planned when custom_tables is empty."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) == 0
    error_message = "No DCR must be planned when custom_tables is empty."
  }
}

# -----------------------------------------------------------------------
# Test 7: validator_severity_out_of_range — severity=5 → failure.
# -----------------------------------------------------------------------
run "validator_severity_out_of_range" {
  command = plan

  variables {
    alerts = {
      bad-alert = {
        kql      = "Perf | summarize count()"
        severity = 5
      }
    }
  }

  expect_failures = [var.alerts]
}

# -----------------------------------------------------------------------
# Test 8: validator_failing_periods_cross_var — min > total → failure.
# -----------------------------------------------------------------------
run "validator_failing_periods_cross_var" {
  command = plan

  variables {
    alerts = {
      bad-alert = {
        kql = "Perf | summarize count()"
        failing_periods = {
          number_of_evaluation_periods             = 2
          minimum_failing_periods_to_trigger_alert = 3
        }
      }
    }
  }

  expect_failures = [var.alerts]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_law_id — malformed law_id → regex failure.
# -----------------------------------------------------------------------
run "validator_invalid_law_id" {
  command = plan

  variables {
    law_id = "not-a-valid-arm-id"
  }

  expect_failures = [var.law_id]
}

# -----------------------------------------------------------------------
# Test 10: validator_invalid_action_group_id — malformed AG ID → regex failure.
# -----------------------------------------------------------------------
run "validator_invalid_action_group_id" {
  command = plan

  variables {
    action_group_ids = ["not-a-valid-arm-id"]
  }

  expect_failures = [var.action_group_ids]
}
