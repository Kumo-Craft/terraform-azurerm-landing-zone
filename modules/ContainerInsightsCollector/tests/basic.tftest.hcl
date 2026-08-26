# Plan-time tests for the ContainerInsightsCollector module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming          — convention naming, no lock, default streams
#   2. happy_name_override           — explicit var.name (XOR escape hatch, F-1)
#   3. happy_with_lock               — var.lock = { kind = "CanNotDelete" }
#   4. happy_no_lock                 — lock module has 0 entries when var.lock = null
#   5. happy_with_role_assignments   — var.role_assignments map → module.role_assignments planned
#   6. happy_tags_merge_createdon    — CreatedOn tag present and var.tags merged
#   7. happy_default_streams         — default streams contain V2, exclude V1 and Perf
#   8. validator_naming_xor_fails    — var.name=null + naming vars=null → XOR failure
#   9. validator_invalid_lock_kind   — lock.kind = "Bogus" → failure
#  10. validator_invalid_workload    — workload starting with digit → failure
#
# Run with:
#   cd modules/ContainerInsightsCollector
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym       = "api"
  environment                = "prod"
  region_code                = "gwc"
  workload                   = "containerinsights"
  location                   = "germanywestcentral"
  resource_group_name        = "rg-api-prod-gwc-aks"
  aks_cluster_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ContainerService/managedClusters/aks-api-prod-gwc"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-law/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, no lock, default streams.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_monitor_data_collection_rule.ci.resource_group_name == "rg-api-prod-gwc-aks"
    error_message = "DCR must be placed in the supplied resource group."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.ci.kind == "Linux"
    error_message = "Container Insights DCR must always use kind = 'Linux'."
  }

  assert {
    condition     = length(module.lock.ids) == 0
    error_message = "No lock must be planned when var.lock is null."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch, F-1).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name                 = "dcr-custom-ci"
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.ci.name == "dcr-custom-ci"
    error_message = "DCR name must match the explicit var.name override."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule_association.ci.name == "dcra-dcr-custom-ci"
    error_message = "DCRA name must be derived from local.name (F-2)."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must NOT be instantiated when var.name is supplied."
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
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_no_lock — module.lock.ids is empty when var.lock = null.
# -----------------------------------------------------------------------
run "happy_no_lock" {
  command = plan

  variables {
    lock = null
  }

  assert {
    condition     = length(module.lock.ids) == 0
    error_message = "Lock module must plan 0 entries when var.lock is null."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_role_assignments — map → role_assignments module entries.
# -----------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      monitoring_reader = {
        role_definition_id_or_name = "Monitoring Reader"
        principal_id               = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  assert {
    condition     = length(module.role_assignments) == 1
    error_message = "role_assignments module must be instantiated once per entry in var.role_assignments."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_tags_merge_createdon — CreatedOn tag is present and merged.
# -----------------------------------------------------------------------
run "happy_tags_merge_createdon" {
  command = plan

  variables {
    tags = { Environment = "Production" }
  }

  assert {
    condition     = contains(keys(azurerm_monitor_data_collection_rule.ci.tags), "CreatedOn")
    error_message = "DCR tags must include the CreatedOn stamp."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.ci.tags["Environment"] == "Production"
    error_message = "DCR tags must include caller-supplied tags merged alongside CreatedOn."
  }
}

# -----------------------------------------------------------------------
# Test 7: happy_default_streams — V2 present, V1 and Perf excluded.
# -----------------------------------------------------------------------
run "happy_default_streams" {
  command = plan

  assert {
    condition     = contains(azurerm_monitor_data_collection_rule.ci.data_flow[0].streams, "Microsoft-ContainerLogV2")
    error_message = "Default streams must include Microsoft-ContainerLogV2."
  }

  assert {
    condition     = !contains(azurerm_monitor_data_collection_rule.ci.data_flow[0].streams, "Microsoft-ContainerLog")
    error_message = "Default streams must NOT include deprecated Microsoft-ContainerLog (V1)."
  }

  assert {
    condition     = !contains(azurerm_monitor_data_collection_rule.ci.data_flow[0].streams, "Microsoft-Perf")
    error_message = "Default streams must NOT include Microsoft-Perf (redundant with Managed Prometheus)."
  }
}

# -----------------------------------------------------------------------
# Test 8: validator_naming_xor_fails — name=null + naming vars null → XOR failure.
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
# Test 9: validator_invalid_lock_kind — "Bogus" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 10: validator_invalid_workload — starts with digit → failure.
# -----------------------------------------------------------------------
run "validator_invalid_workload" {
  command = plan

  variables {
    workload = "1invalid"
  }

  expect_failures = [var.workload]
}
