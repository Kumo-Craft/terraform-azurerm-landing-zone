# Plan-time tests for the LogAnalyticsWorkspace module.
#
# Mocks azurerm + time; the Naming submodule's random provider runs for real.
#
# Covers:
#   1. happy_default   — ../Naming slug + secure-by-default posture
#   2. name_override   — var.name wins, Naming module not instantiated
#   3. capacity_reservation — CapacityReservation + commitment tier
#   4. with_identity   — optional SystemAssigned identity block
#   5. with_lock       — optional lock scoped to the workspace
#   6. validator_retention_below_min     — 29 days → fail
#   7. validator_retention_above_max     — 731 days → fail
#   8. validator_daily_quota_zero        — 0 → fail (must be -1 or > 0)
#   9. validator_bad_sku                 — invalid sku → fail
#  10. validator_reservation_without_sku — capacity without CapacityReservation → fail
#  11. validator_bad_reservation_tier    — 150 GB/day → fail
#  12. validator_name_starts_with_hyphen — invalid name → fail
#  13. validator_user_assigned_without_ids — UserAssigned + no ids → fail
#
# Run with:
#   cd modules/LogAnalyticsWorkspace
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs.
variables {
  subscription_acronym = "sec"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "soc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-sec-prod-gwc-soc"
}

# -----------------------------------------------------------------------
# Test 1: happy_default — derived name + hardened posture.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-sec-prod-gwc-soc"
    error_message = "Name must derive from ../Naming as log-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.local_authentication_enabled == false
    error_message = "Local (workspace-key) auth must be OFF by default → Entra ID only."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.internet_ingestion_enabled == false && azurerm_log_analytics_workspace.this.internet_query_enabled == false
    error_message = "Public ingestion/query must be OFF by default (private via AMPLS)."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.allow_resource_only_permissions == true
    error_message = "allow_resource_only_permissions must default to true (resource-context RBAC)."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018" && azurerm_log_analytics_workspace.this.retention_in_days == 30 && azurerm_log_analytics_workspace.this.daily_quota_gb == -1
    error_message = "Defaults must be PerGB2018 / 30 days / no daily cap (-1)."
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.this.identity) == 0
    error_message = "No identity block by default."
  }
}

# -----------------------------------------------------------------------
# Test 2: name_override — escape hatch (e.g. legacy law- prefix).
# -----------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name = "law-sec-prod-gwc-01"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "law-sec-prod-gwc-01"
    error_message = "var.name must override the derived name (byte-for-byte)."
  }
}

# -----------------------------------------------------------------------
# Test 3: capacity_reservation — commitment tier.
# -----------------------------------------------------------------------
run "capacity_reservation" {
  command = plan

  variables {
    sku                                = "CapacityReservation"
    reservation_capacity_in_gb_per_day = 200
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.reservation_capacity_in_gb_per_day == 200
    error_message = "Commitment tier must pass through when sku = CapacityReservation."
  }
}

# -----------------------------------------------------------------------
# Test 4: with_identity — optional SystemAssigned identity.
# -----------------------------------------------------------------------
run "with_identity" {
  command = plan

  variables {
    identity = { type = "SystemAssigned" }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.identity[0].type == "SystemAssigned"
    error_message = "identity block must be rendered when var.identity is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: with_lock — optional lock.
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
# Test 6: validator_retention_below_min — 29 → fail.
# -----------------------------------------------------------------------
run "validator_retention_below_min" {
  command = plan

  variables {
    retention_in_days = 29
  }

  expect_failures = [var.retention_in_days]
}

# -----------------------------------------------------------------------
# Test 7: validator_retention_above_max — 731 → fail.
# -----------------------------------------------------------------------
run "validator_retention_above_max" {
  command = plan

  variables {
    retention_in_days = 731
  }

  expect_failures = [var.retention_in_days]
}

# -----------------------------------------------------------------------
# Test 8: validator_daily_quota_zero — 0 → fail.
# -----------------------------------------------------------------------
run "validator_daily_quota_zero" {
  command = plan

  variables {
    daily_quota_gb = 0
  }

  expect_failures = [var.daily_quota_gb]
}

# -----------------------------------------------------------------------
# Test 9: validator_bad_sku — invalid enum → fail.
# -----------------------------------------------------------------------
run "validator_bad_sku" {
  command = plan

  variables {
    sku = "Free"
  }

  expect_failures = [var.sku]
}

# -----------------------------------------------------------------------
# Test 10: validator_reservation_without_sku — capacity set on PerGB2018.
# -----------------------------------------------------------------------
run "validator_reservation_without_sku" {
  command = plan

  variables {
    sku                                = "PerGB2018"
    reservation_capacity_in_gb_per_day = 200
  }

  expect_failures = [var.reservation_capacity_in_gb_per_day]
}

# -----------------------------------------------------------------------
# Test 11: validator_bad_reservation_tier — 150 is not an allowed tier.
# -----------------------------------------------------------------------
run "validator_bad_reservation_tier" {
  command = plan

  variables {
    sku                                = "CapacityReservation"
    reservation_capacity_in_gb_per_day = 150
  }

  expect_failures = [var.reservation_capacity_in_gb_per_day]
}

# -----------------------------------------------------------------------
# Test 12: validator_name_starts_with_hyphen — invalid name.
# -----------------------------------------------------------------------
run "validator_name_starts_with_hyphen" {
  command = plan

  variables {
    name = "-log-bad-name"
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 13: validator_user_assigned_without_ids — UserAssigned + no ids.
# -----------------------------------------------------------------------
run "validator_user_assigned_without_ids" {
  command = plan

  variables {
    identity = { type = "UserAssigned" }
  }

  expect_failures = [var.identity]
}
