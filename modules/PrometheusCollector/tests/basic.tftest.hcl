# Plan-time tests for the PrometheusCollector module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming         — convention naming, no recording rules, no lock
#   2. happy_name_override          — explicit var.name (XOR escape hatch, F-2)
#   3. happy_with_recording_rules   — enable_recording_rules = true → rule groups planned
#   4. happy_with_lock              — var.lock = { kind = "CanNotDelete" }
#   5. happy_no_kind_on_dcr         — F-1: kind attribute omitted, DCR name follows convention
#   6. validator_naming_xor_fails   — var.name = null + naming vars = null → XOR failure
#   7. validator_invalid_lock_kind  — lock.kind = "Bogus" → failure
#
# Run with:
#   cd modules/PrometheusCollector
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym        = "api"
  environment                 = "prod"
  region_code                 = "gwc"
  workload                    = "prometheus"
  location                    = "germanywestcentral"
  resource_group_name         = "rg-api-prod-gwc-aks"
  aks_cluster_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ContainerService/managedClusters/aks-api-prod-gwc"
  aks_cluster_name            = "aks-api-prod-gwc"
  monitor_workspace_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Monitor/accounts/amw-mgm-prod-gwc-01"
  data_collection_endpoint_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Insights/dataCollectionEndpoints/dce-mgm-prod-gwc-01"
  enable_recording_rules      = false
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, no lock, no recording rules.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_monitor_data_collection_rule.prometheus.resource_group_name == "rg-api-prod-gwc-aks"
    error_message = "DCR must be placed in the supplied resource group."
  }

  assert {
    condition     = length(module.lock.ids) == 0
    error_message = "No lock must be planned when var.lock is null."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch, F-2).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name                 = "dcr-custom"
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.prometheus.name == "dcr-custom"
    error_message = "DCR name must match the explicit var.name override."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must NOT be instantiated when var.name is supplied."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_recording_rules — recording rule groups planned.
# -----------------------------------------------------------------------
run "happy_with_recording_rules" {
  command = plan

  variables {
    enable_recording_rules = true
  }

  assert {
    condition     = length(azurerm_monitor_alert_prometheus_rule_group.node_recording) == 1
    error_message = "Node recording rule group must be planned when enable_recording_rules = true."
  }

  assert {
    condition     = length(azurerm_monitor_alert_prometheus_rule_group.k8s_recording) == 1
    error_message = "Kubernetes recording rule group must be planned when enable_recording_rules = true."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_lock — var.lock = { kind = "CanNotDelete" }.
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_no_kind_on_dcr — F-1: kind is not set (null) on the DCR.
# The DCR name follows convention when no override is given.
# -----------------------------------------------------------------------
run "happy_no_kind_on_dcr" {
  command = plan

  assert {
    condition     = azurerm_monitor_data_collection_rule.prometheus.kind == null
    error_message = "F-1: kind must NOT be set on a Prometheus forwarder DCR (must be null, not 'Linux')."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_naming_xor_fails — name=null + naming vars null → XOR failure.
# -----------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_lock_kind — "Bogus" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}
