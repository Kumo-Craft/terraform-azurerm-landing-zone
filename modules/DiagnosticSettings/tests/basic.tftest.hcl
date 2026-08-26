# Plan-time tests for the DiagnosticSettings module.
#
# Mocks azurerm. Covers:
#   1. happy_law_destination_alllogs       — LAW + log_groups=["allLogs"], assert resource planned
#   2. happy_multi_destination             — LAW + storage + EventHub on single setting
#   3. happy_per_category_vs_per_group     — 2 entries: one with logs=[], one with log_groups=["audit"]
#   4. happy_dedicated_destination_type    — log_analytics_destination_type="Dedicated"
#   5. validator_invalid_log_groups        — log_groups=["alllogs"] (lowercase) → F-1 failure
#   6. validator_invalid_log_groups_unknown — log_groups=["custom"] → F-1 failure
#   7. validator_invalid_target_resource_id — bad ARM ID format → existing validator failure
#   8. validator_no_destination            — no LAW/storage/EventHub/partner → at-least-one-destination failure
#   9. validator_invalid_law_id            — workspace GUID instead of ARM resource ID → F-2 failure
#
# Run with:
#   cd modules/DiagnosticSettings
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# -----------------------------------------------------------------------
# Test 1: happy_law_destination_alllogs
# Single diag setting with LAW + log_groups=["allLogs"].
# -----------------------------------------------------------------------
run "happy_law_destination_alllogs" {
  command = plan

  variables {
    diagnostic_settings = {
      vnet = {
        name                       = "diag-vnet-prod"
        target_resource_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net-prod-gwc/providers/Microsoft.Network/virtualNetworks/vnet-prod-gwc-001"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        log_groups                 = ["allLogs"]
        metrics                    = ["AllMetrics"]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Exactly 1 diagnostic setting must be planned."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["vnet"].name == "diag-vnet-prod"
    error_message = "Diagnostic setting name must match the provided value."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["vnet"].log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
    error_message = "log_analytics_workspace_id must be wired to the resource."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_multi_destination
# LAW + storage + EventHub all set on a single diag setting.
# -----------------------------------------------------------------------
run "happy_multi_destination" {
  command = plan

  variables {
    diagnostic_settings = {
      aks = {
        name                            = "diag-aks-prod"
        target_resource_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc/providers/Microsoft.ContainerService/managedClusters/aks-app-prod-gwc-001"
        log_analytics_workspace_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        storage_account_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.Storage/storageAccounts/stmgmprodgwc01"
        event_hub_authorization_rule_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.EventHub/namespaces/evhns-mgm-prod-gwc-01/authorizationRules/RootManageSharedAccessKey"
        event_hub_name                  = "evh-diag-prod"
        log_groups                      = ["allLogs"]
        metrics                         = ["AllMetrics"]
      }
    }
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["aks"].storage_account_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.Storage/storageAccounts/stmgmprodgwc01"
    error_message = "storage_account_id must be wired to the resource."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["aks"].eventhub_authorization_rule_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.EventHub/namespaces/evhns-mgm-prod-gwc-01/authorizationRules/RootManageSharedAccessKey"
    error_message = "eventhub_authorization_rule_id must be wired to the resource."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["aks"].eventhub_name == "evh-diag-prod"
    error_message = "eventhub_name must be wired to the resource."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_per_category_vs_per_group
# 2 entries: one with per-category logs, one with per-group log_groups.
# Both must be planned without error.
# -----------------------------------------------------------------------
run "happy_per_category_vs_per_group" {
  command = plan

  variables {
    diagnostic_settings = {
      kv_per_category = {
        name                       = "diag-kv-category"
        target_resource_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec-prod-gwc/providers/Microsoft.KeyVault/vaults/kv-sec-prod-gwc-01"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        logs                       = ["AuditEvent"]
      }
      kv_per_group = {
        name                       = "diag-kv-group"
        target_resource_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec-prod-gwc/providers/Microsoft.KeyVault/vaults/kv-sec-prod-gwc-02"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        log_groups                 = ["audit"]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 2
    error_message = "Exactly 2 diagnostic settings must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_dedicated_destination_type
# log_analytics_destination_type = "Dedicated" must flow through.
# -----------------------------------------------------------------------
run "happy_dedicated_destination_type" {
  command = plan

  variables {
    diagnostic_settings = {
      aks_dedicated = {
        name                           = "diag-aks-dedicated"
        target_resource_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc/providers/Microsoft.ContainerService/managedClusters/aks-app-prod-gwc-001"
        log_analytics_workspace_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        log_analytics_destination_type = "Dedicated"
        log_groups                     = ["allLogs"]
        metrics                        = ["AllMetrics"]
      }
    }
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["aks_dedicated"].log_analytics_destination_type == "Dedicated"
    error_message = "log_analytics_destination_type must be 'Dedicated' as provided."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_invalid_log_groups — lowercase "alllogs" typo → F-1 failure.
# -----------------------------------------------------------------------
run "validator_invalid_log_groups" {
  command = plan

  variables {
    diagnostic_settings = {
      bad = {
        name                       = "diag-bad"
        target_resource_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net-prod-gwc/providers/Microsoft.Network/virtualNetworks/vnet-prod-gwc-001"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        log_groups                 = ["alllogs"]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}

# -----------------------------------------------------------------------
# Test 6: validator_invalid_log_groups_unknown — "custom" is not a valid group → F-1 failure.
# -----------------------------------------------------------------------
run "validator_invalid_log_groups_unknown" {
  command = plan

  variables {
    diagnostic_settings = {
      bad = {
        name                       = "diag-bad"
        target_resource_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net-prod-gwc/providers/Microsoft.Network/virtualNetworks/vnet-prod-gwc-001"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        log_groups                 = ["custom"]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_target_resource_id — bad ARM ID format → existing validator failure.
# -----------------------------------------------------------------------
run "validator_invalid_target_resource_id" {
  command = plan

  variables {
    diagnostic_settings = {
      bad = {
        name                       = "diag-bad"
        target_resource_id         = "not-a-valid-resource-id"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
        log_groups                 = ["allLogs"]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}

# -----------------------------------------------------------------------
# Test 8: validator_no_destination — no destination set → at-least-one-destination failure.
# -----------------------------------------------------------------------
run "validator_no_destination" {
  command = plan

  variables {
    diagnostic_settings = {
      bad = {
        name               = "diag-bad"
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net-prod-gwc/providers/Microsoft.Network/virtualNetworks/vnet-prod-gwc-001"
        log_groups         = ["allLogs"]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_law_id — workspace GUID instead of ARM resource ID → F-2 failure.
# -----------------------------------------------------------------------
run "validator_invalid_law_id" {
  command = plan

  variables {
    diagnostic_settings = {
      bad = {
        name                       = "diag-bad"
        target_resource_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net-prod-gwc/providers/Microsoft.Network/virtualNetworks/vnet-prod-gwc-001"
        log_analytics_workspace_id = "12345678-1234-1234-1234-123456789012"
        log_groups                 = ["allLogs"]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}
