# Plan-time tests for the AvdInsightsCollector module.
#
# Mocks azurerm + time; the Naming submodule's random provider runs for real.
#
# Covers:
#   1. happy_default        — naming, kind, streams, MS counter/event defaults, no associations
#   2. with_session_hosts   — one association per session host
#   3. name_override        — var.name wins
#   4. with_lock            — optional lock
#   5. counter_override     — callers can trim/replace the counter set
#   6. validator_bad_law_id            — not a LAW ARM id → fail
#   7. validator_empty_perf_counters   — [] → fail
#   8. validator_bad_sampling_frequency— 3600s → fail
#   9. validator_empty_event_logs      — [] → fail
#
# Run with:
#   cd modules/AvdInsightsCollector
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs.
variables {
  subscription_acronym       = "avd"
  environment                = "prod"
  region_code                = "gwc"
  location                   = "germanywestcentral"
  resource_group_name        = "rg-avd-prod-gwc-monitoring"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-prod-gwc-monitoring/providers/Microsoft.OperationalInsights/workspaces/log-avd-prod-gwc-01"
}

# -----------------------------------------------------------------------
# Test 1: happy_default — naming + Microsoft defaults.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  assert {
    condition     = azurerm_monitor_data_collection_rule.avd.name == "dcr-avd-prod-gwc-01-avdinsights"
    error_message = "Name must derive as dcr-{acr}-{env}-{region}-{workload}-avdinsights."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.avd.kind == "Windows"
    error_message = "DCR kind must be Windows (session hosts)."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.avd.data_flow) == 2
    error_message = "Two data flows must be planned (Microsoft-Perf and Microsoft-Event)."
  }

  assert {
    condition = alltrue([
      for f in azurerm_monitor_data_collection_rule.avd.data_flow :
      contains([tolist(["Microsoft-Perf"]), tolist(["Microsoft-Event"])], tolist(f.streams))
    ])
    error_message = "Data flows must use Microsoft-Perf / Microsoft-Event (NOT Microsoft-InsightsMetrics — not read by AVD Insights)."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.avd.data_sources[0].performance_counter) == 2
    error_message = "Two performance_counter blocks must be planned (30s and 60s frequencies)."
  }

  assert {
    condition = length([
      for p in azurerm_monitor_data_collection_rule.avd.data_sources[0].performance_counter :
      p if p.sampling_frequency_in_seconds == 30 && length(p.counter_specifiers) == 15
    ]) == 1
    error_message = "The 30s block must carry the 15 AVD Insights counters."
  }

  assert {
    condition = length([
      for p in azurerm_monitor_data_collection_rule.avd.data_sources[0].performance_counter :
      p if p.sampling_frequency_in_seconds == 60 && length(p.counter_specifiers) == 5
    ]) == 1
    error_message = "The 60s block must carry the 5 AVD Insights counters."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.avd.data_sources[0].windows_event_log[0].x_path_queries) == 6
    error_message = "The six AVD Insights event logs must be collected."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule_association.avd) == 0
    error_message = "No associations by default (session_host_ids = [] so the DCR can be created before the hosts)."
  }
}

# -----------------------------------------------------------------------
# Test 2: with_session_hosts — one association per host.
# -----------------------------------------------------------------------
run "with_session_hosts" {
  command = plan

  variables {
    session_host_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-prod-gwc-hosts/providers/Microsoft.Compute/virtualMachines/vm-avd-01",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-prod-gwc-hosts/providers/Microsoft.Compute/virtualMachines/vm-avd-02",
    ]
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule_association.avd) == 2
    error_message = "One DCR association must be planned per session host."
  }
}

# -----------------------------------------------------------------------
# Test 3: name_override — escape hatch.
# -----------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name = "dcr-legacy-avdinsights"
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule.avd.name == "dcr-legacy-avdinsights"
    error_message = "var.name must override the derived name."
  }
}

# -----------------------------------------------------------------------
# Test 4: with_lock — optional lock.
# -----------------------------------------------------------------------
run "with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "One lock must be planned when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: counter_override — trimmed counter set.
# -----------------------------------------------------------------------
run "counter_override" {
  command = plan

  variables {
    performance_counters = [
      {
        name                          = "minimal"
        sampling_frequency_in_seconds = 60
        counter_specifiers            = ["\\Processor Information(_Total)\\% Processor Time"]
      }
    ]
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.avd.data_sources[0].performance_counter) == 1
    error_message = "performance_counters override must replace the default set."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_bad_law_id — not a workspace ARM id.
# -----------------------------------------------------------------------
run "validator_bad_law_id" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg"
  }

  expect_failures = [var.log_analytics_workspace_id]
}

# -----------------------------------------------------------------------
# Test 7: validator_empty_perf_counters — [] → fail.
# -----------------------------------------------------------------------
run "validator_empty_perf_counters" {
  command = plan

  variables {
    performance_counters = []
  }

  expect_failures = [var.performance_counters]
}

# -----------------------------------------------------------------------
# Test 8: validator_bad_sampling_frequency — 3600s → fail.
# -----------------------------------------------------------------------
run "validator_bad_sampling_frequency" {
  command = plan

  variables {
    performance_counters = [
      {
        name                          = "too-slow"
        sampling_frequency_in_seconds = 3600
        counter_specifiers            = ["\\Memory(*)\\Available Mbytes"]
      }
    ]
  }

  expect_failures = [var.performance_counters]
}

# -----------------------------------------------------------------------
# Test 9: validator_empty_event_logs — [] → fail.
# -----------------------------------------------------------------------
run "validator_empty_event_logs" {
  command = plan

  variables {
    windows_event_logs = []
  }

  expect_failures = [var.windows_event_logs]
}
