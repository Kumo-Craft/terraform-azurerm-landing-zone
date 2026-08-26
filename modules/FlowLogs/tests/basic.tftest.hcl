# Plan-time tests for the FlowLogs module.
#
# Mocks azurerm + time. Covers:
#   1.  happy_default_single_vnet            — minimal single VNet plans cleanly
#   2.  happy_multi_vnet                     — 3 VNets in map
#   3.  happy_with_traffic_analytics_10      — 10-min interval LAW path
#   4.  happy_with_traffic_analytics_60      — 60-min interval LAW path
#   5.  happy_with_lock_and_rbac             — per-vnet lock + role assignment
#   6.  happy_with_name_override             — per-entry name nullable override (F-3)
#   7.  happy_retention_zero                 — F-9 path: retention_days=0 plans cleanly
#   8.  validator_storage_account_id_arm_regex    — malformed storage ID fails
#   9.  validator_vnet_id_arm_regex (F-10)        — NSG ID passed as VNet ID fails
#  10.  validator_traffic_analytics_interval_enum — invalid interval fails
#  11.  validator_lock_kind_enum                  — invalid lock kind fails
#  12.  validator_role_assignments_principal_type — invalid principal_type fails
#  13.  validator_workload_xor_per_entry_name     — neither workload nor name fails (F-4)
#  14.  validator_retention_days_range            — retention_days > 365 fails
#
# Run with:
#   cd modules/FlowLogs
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym = "con"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "network"
  location             = "germanywestcentral"

  network_watcher_name                = "NetworkWatcher_germanywestcentral"
  network_watcher_resource_group_name = "NetworkWatcherRG"
  storage_account_id                  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-flowlogs/providers/Microsoft.Storage/storageAccounts/stconnprdgwcflowlogs"

  vnets = {
    spoke = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke"
    }
  }
}

# -----------------------------------------------------------------------
# Test 1: happy_default_single_vnet — minimal single VNet plans cleanly.
# -----------------------------------------------------------------------
run "happy_default_single_vnet" {
  command = plan

  assert {
    condition     = length(azurerm_network_watcher_flow_log.this) == 1
    error_message = "Exactly one flow log resource must be planned for a single-entry vnets map."
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.this["spoke"].name == "fl-con-nprd-gwc-network-spoke"
    error_message = "Flow log name must follow fl-{acr}-{env}-{region}-{workload}-{vnet_key} convention."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_multi_vnet — 3 VNets in map.
# -----------------------------------------------------------------------
run "happy_multi_vnet" {
  command = plan

  variables {
    vnets = {
      spoke1 = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke1"
      }
      spoke2 = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke2"
      }
      nva = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-nva"
      }
    }
  }

  assert {
    condition     = length(azurerm_network_watcher_flow_log.this) == 3
    error_message = "Three flow log resources must be planned for a 3-entry vnets map."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_traffic_analytics_10 — 10-min interval LAW path.
# -----------------------------------------------------------------------
run "happy_with_traffic_analytics_10" {
  command = plan

  variables {
    traffic_analytics = {
      workspace_id          = "82f9d847-335e-4441-adee-38a48dd8a613"
      workspace_region      = "germanywestcentral"
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-nprd-gwc-core/providers/Microsoft.OperationalInsights/workspaces/law-mgm-nprd-gwc-core"
      interval_minutes      = 10
    }
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.this["spoke"].traffic_analytics[0].interval_in_minutes == 10
    error_message = "traffic_analytics.interval_in_minutes must be 10 when interval_minutes = 10."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_traffic_analytics_60 — 60-min interval LAW path.
# -----------------------------------------------------------------------
run "happy_with_traffic_analytics_60" {
  command = plan

  variables {
    traffic_analytics = {
      workspace_id          = "82f9d847-335e-4441-adee-38a48dd8a613"
      workspace_region      = "germanywestcentral"
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-nprd-gwc-core/providers/Microsoft.OperationalInsights/workspaces/law-mgm-nprd-gwc-core"
      interval_minutes      = 60
    }
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.this["spoke"].traffic_analytics[0].interval_in_minutes == 60
    error_message = "traffic_analytics.interval_in_minutes must be 60 when interval_minutes = 60."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_lock_and_rbac — per-vnet lock + role assignment.
# -----------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    vnets = {
      spoke = {
        id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke"
        enabled = true
        lock = {
          kind = "CanNotDelete"
          name = "lock-spoke-flowlog"
        }
        role_assignments = {
          reader = {
            role_definition_id_or_name = "Reader"
            principal_id               = "00000000-0000-0000-0000-000000000010"
            principal_type             = "Group"
          }
        }
      }
    }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when vnets[*].lock is set."
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "RBAC module must plan 1 entry matching the role_assignments map."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_with_name_override — per-entry name nullable override (F-3).
# -----------------------------------------------------------------------
run "happy_with_name_override" {
  command = plan

  variables {
    vnets = {
      spoke = {
        id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke"
        name = "fl-con-nprd-gwc-spoke-custom"
      }
    }
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.this["spoke"].name == "fl-con-nprd-gwc-spoke-custom"
    error_message = "Flow log name must match the per-entry name override."
  }
}

# -----------------------------------------------------------------------
# Test 7: happy_retention_zero — F-9 path: retention_days=0 plans cleanly.
# Retention policy is sent as {enabled=false, days=0} — SA lifecycle governs.
# -----------------------------------------------------------------------
run "happy_retention_zero" {
  command = plan

  variables {
    retention_days = 0
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.this["spoke"].retention_policy[0].enabled == false
    error_message = "When retention_days=0, retention_policy.enabled must be false."
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.this["spoke"].retention_policy[0].days == 0
    error_message = "When retention_days=0, retention_policy.days must be 0."
  }
}

# -----------------------------------------------------------------------
# Test 8: validator_storage_account_id_arm_regex — malformed storage ID fails.
# -----------------------------------------------------------------------
run "validator_storage_account_id_arm_regex" {
  command = plan

  variables {
    storage_account_id = "not-a-valid-arm-id"
  }

  expect_failures = [var.storage_account_id]
}

# -----------------------------------------------------------------------
# Test 9: validator_vnet_id_arm_regex (F-10) — passing NSG ID fails.
# Prevents silent regression to deprecated NSG flow logs (EOL 2027-09-30).
# -----------------------------------------------------------------------
run "validator_vnet_id_arm_regex" {
  command = plan

  variables {
    vnets = {
      spoke = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/networkSecurityGroups/nsg-con-nprd-gwc-spoke"
      }
    }
  }

  expect_failures = [var.vnets]
}

# -----------------------------------------------------------------------
# Test 10: validator_traffic_analytics_interval_enum — invalid interval fails.
# -----------------------------------------------------------------------
run "validator_traffic_analytics_interval_enum" {
  command = plan

  variables {
    traffic_analytics = {
      workspace_id          = "82f9d847-335e-4441-adee-38a48dd8a613"
      workspace_region      = "germanywestcentral"
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-nprd-gwc-core/providers/Microsoft.OperationalInsights/workspaces/law-mgm-nprd-gwc-core"
      interval_minutes      = 30
    }
  }

  expect_failures = [var.traffic_analytics]
}

# -----------------------------------------------------------------------
# Test 11: validator_lock_kind_enum — invalid lock kind fails.
# -----------------------------------------------------------------------
run "validator_lock_kind_enum" {
  command = plan

  variables {
    vnets = {
      spoke = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke"
        lock = {
          kind = "Bogus"
        }
      }
    }
  }

  expect_failures = [var.vnets]
}

# -----------------------------------------------------------------------
# Test 12: validator_role_assignments_principal_type_enum — invalid principal_type fails.
# -----------------------------------------------------------------------
run "validator_role_assignments_principal_type_enum" {
  command = plan

  variables {
    vnets = {
      spoke = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke"
        role_assignments = {
          bad_entry = {
            role_definition_id_or_name = "Reader"
            principal_id               = "00000000-0000-0000-0000-000000000010"
            principal_type             = "Invalid"
          }
        }
      }
    }
  }

  expect_failures = [var.vnets]
}

# -----------------------------------------------------------------------
# Test 13: validator_workload_xor_per_entry_name — neither workload nor
# per-entry name set fails (F-4 cross-var).
# -----------------------------------------------------------------------
run "validator_workload_xor_per_entry_name" {
  command = plan

  variables {
    workload = null
    vnets = {
      spoke = {
        id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-con-nprd-gwc-spoke"
        # name is null (default) — neither workload nor name is set
      }
    }
  }

  expect_failures = [var.workload]
}

# -----------------------------------------------------------------------
# Test 14: validator_retention_days_range — retention_days > 365 fails.
# -----------------------------------------------------------------------
run "validator_retention_days_range" {
  command = plan

  variables {
    retention_days = 366
  }

  expect_failures = [var.retention_days]
}
