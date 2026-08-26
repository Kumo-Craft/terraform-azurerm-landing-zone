# Plan-time tests for the PrometheusAlertRules module.
#
# Mocks azurerm + time. Covers:
#   1. happy_amw_only              — AMW-only scope (no AKS), 1 rule group, scopes has 1 entry
#   2. happy_amw_plus_aks          — AMW + AKS, scopes has 2 entries
#   3. happy_with_lock             — var.lock = { kind = "CanNotDelete" }, lock planned per group
#   4. happy_multi_action_group    — action_group_ids = [A, B, C], 3 actions per rule
#   5. happy_alert_resolution_override — explicit time_to_resolve = "PT30M" flows through
#   6. validator_action_group_ids_empty    — [] → length>=1 failure
#   7. validator_action_group_ids_too_many — 6 entries → length<=5 failure
#   8. validator_invalid_action_group_id   — invalid ARM ID → regex failure
#   9. validator_severity_out_of_range     — severity = 5 → failure
#  10. validator_aks_only_cluster_id       — aks_cluster_id set + aks_cluster_name null → cross-var failure
#
# Run with:
#   cd modules/PrometheusAlertRules
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-aks"
  monitor_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Monitor/accounts/amw-mgm-prod-gwc-01"
  action_group_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Insights/actionGroups/ag-api-prod-gwc-aks"
  ]
  rule_groups = {
    "node-cpu" = {
      interval = "PT1M"
      alerts = {
        "NodeCPUHigh" = {
          expression = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 90"
          severity   = 2
        }
      }
    }
  }
}

# -----------------------------------------------------------------------
# Test 1: happy_amw_only — AMW-only scope (no AKS cluster).
# -----------------------------------------------------------------------
run "happy_amw_only" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_alert_prometheus_rule_group.this["node-cpu"].scopes) == 1
    error_message = "AMW-only scope must have exactly 1 entry in scopes."
  }

  assert {
    condition     = azurerm_monitor_alert_prometheus_rule_group.this["node-cpu"].name == "node-cpu"
    error_message = "AMW-only resource name must equal the rule group key when aks_cluster_name is null."
  }

  assert {
    condition     = length(module.lock.ids) == 0
    error_message = "No lock must be planned when var.lock is null."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_amw_plus_aks — AMW + AKS, scopes has 2 entries.
# -----------------------------------------------------------------------
run "happy_amw_plus_aks" {
  command = plan

  variables {
    aks_cluster_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ContainerService/managedClusters/aks-api-prod-gwc"
    aks_cluster_name = "aks-api-prod-gwc"
  }

  assert {
    condition     = length(azurerm_monitor_alert_prometheus_rule_group.this["node-cpu"].scopes) == 2
    error_message = "AMW+AKS scope must have exactly 2 entries in scopes."
  }

  assert {
    condition     = azurerm_monitor_alert_prometheus_rule_group.this["node-cpu"].name == "node-cpu-aks-api-prod-gwc"
    error_message = "Resource name must be '<group-key>-<cluster-name>' when aks_cluster_name is set."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_lock — var.lock = { kind = "CanNotDelete" }.
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry per rule group when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_multi_action_group — 3 action groups wired.
# -----------------------------------------------------------------------
run "happy_multi_action_group" {
  command = plan

  variables {
    action_group_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Insights/actionGroups/ag-api-prod-gwc-01",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Insights/actionGroups/ag-api-prod-gwc-02",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Insights/actionGroups/ag-api-prod-gwc-03",
    ]
  }

  assert {
    condition     = length(azurerm_monitor_alert_prometheus_rule_group.this["node-cpu"].rule[0].action) == 3
    error_message = "Must have 3 action entries when 3 action_group_ids are provided."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_alert_resolution_override — explicit time_to_resolve = "PT30M".
# -----------------------------------------------------------------------
run "happy_alert_resolution_override" {
  command = plan

  variables {
    rule_groups = {
      "node-cpu" = {
        interval = "PT1M"
        alerts = {
          "NodeCPUHigh" = {
            expression = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 90"
            severity   = 2
            alert_resolution = {
              auto_resolved   = true
              time_to_resolve = "PT30M"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = azurerm_monitor_alert_prometheus_rule_group.this["node-cpu"].rule[0].alert_resolution[0].time_to_resolve == "PT30M"
    error_message = "alert_resolution.time_to_resolve override must flow through to the resource."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_action_group_ids_empty — [] → length>=1 failure.
# -----------------------------------------------------------------------
run "validator_action_group_ids_empty" {
  command = plan

  variables {
    action_group_ids = []
  }

  expect_failures = [var.action_group_ids]
}

# -----------------------------------------------------------------------
# Test 7: validator_action_group_ids_too_many — 6 entries → length<=5 failure.
# -----------------------------------------------------------------------
run "validator_action_group_ids_too_many" {
  command = plan

  variables {
    action_group_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag1",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag2",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag3",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag4",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag5",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag6",
    ]
  }

  expect_failures = [var.action_group_ids]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_action_group_id — invalid ARM ID → regex failure.
# -----------------------------------------------------------------------
run "validator_invalid_action_group_id" {
  command = plan

  variables {
    action_group_ids = ["not-a-valid-arm-id"]
  }

  expect_failures = [var.action_group_ids]
}

# -----------------------------------------------------------------------
# Test 9: validator_severity_out_of_range — severity = 5 → failure.
# -----------------------------------------------------------------------
run "validator_severity_out_of_range" {
  command = plan

  variables {
    rule_groups = {
      "node-cpu" = {
        interval = "PT1M"
        alerts = {
          "NodeCPUHigh" = {
            expression = "up == 0"
            severity   = 5
          }
        }
      }
    }
  }

  expect_failures = [var.rule_groups]
}

# -----------------------------------------------------------------------
# Test 10: validator_aks_only_cluster_id — aks_cluster_id set + aks_cluster_name null → failure.
# -----------------------------------------------------------------------
run "validator_aks_only_cluster_id" {
  command = plan

  variables {
    aks_cluster_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ContainerService/managedClusters/aks-api-prod-gwc"
    aks_cluster_name = null
  }

  expect_failures = [var.aks_cluster_name]
}
