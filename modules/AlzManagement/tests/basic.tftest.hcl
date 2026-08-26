# Plan-time tests for the AlzManagement module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default       — caller-provided RG, all defaults, assert plan completes
#   2. happy_create_rg     — create_resource_group = true, assert RG resource planned
#   3. happy_with_lock     — var.lock = { kind = "CanNotDelete" }, assert lock map has 2 entries
#   4. happy_workload_override — custom var.workload
#   5. happy_retention_custom  — log_retention_days = 365
#   6. validator_create_rg_false_no_name — create_resource_group=false + resource_group_name=null → failure
#   7. validator_log_retention_below_min — log_retention_days = 7 → failure
#   8. validator_log_retention_above_max — log_retention_days = 5000 → failure
#   9. validator_invalid_lock_kind       — lock.kind = "Bogus" → failure
#
# Run with:
#   cd modules/AlzManagement
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-management"
}

# -----------------------------------------------------------------------
# Test 1: happy_default — caller-provided RG, all variable defaults.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  # override_data so the azurerm mock satisfies the data.azurerm_resource_group.this lookup
  override_data {
    target = data.azurerm_resource_group.this[0]
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management"
      location = "germanywestcentral"
      name     = "rg-mgm-prod-gwc-management"
    }
  }

  assert {
    condition     = output.resource_group_name == "rg-mgm-prod-gwc-management"
    error_message = "resource_group_name output must reflect the caller-provided RG."
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 0
    error_message = "No inline RG should be created when create_resource_group=false."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_create_rg — inline resource group creation.
# -----------------------------------------------------------------------
run "happy_create_rg" {
  command = plan

  variables {
    create_resource_group = true
    resource_group_name   = null
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 1
    error_message = "One inline RG must be planned when create_resource_group=true."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_lock — CanNotDelete on LAW + RG.
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    create_resource_group = true
    resource_group_name   = null
    lock                  = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 2
    error_message = "Lock module must plan 2 lock entries (law + rg) when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_workload_override — custom workload suffix in resource names.
# -----------------------------------------------------------------------
run "happy_workload_override" {
  command = plan

  variables {
    workload            = "sentinel"
    resource_group_name = "rg-mgm-prod-gwc-management"
  }

  override_data {
    target = data.azurerm_resource_group.this[0]
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management"
      location = "germanywestcentral"
      name     = "rg-mgm-prod-gwc-management"
    }
  }

  assert {
    # The LAW identity resource was removed; assert workload propagation on the
    # workspace name instead (Naming submodule → …-{workload}).
    condition     = endswith(output.law_name, "-sentinel")
    error_message = "workload override must propagate into the LAW name (…-sentinel)."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_retention_custom — log_retention_days = 365 (within bounds).
# -----------------------------------------------------------------------
run "happy_retention_custom" {
  command = plan

  variables {
    log_retention_days = 365
  }

  override_data {
    target = data.azurerm_resource_group.this[0]
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management"
      location = "germanywestcentral"
      name     = "rg-mgm-prod-gwc-management"
    }
  }

  assert {
    condition     = output.resource_group_name == "rg-mgm-prod-gwc-management"
    error_message = "Plan must succeed with log_retention_days = 365."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_create_rg_false_no_name — must fail with F-10 error.
# -----------------------------------------------------------------------
run "validator_create_rg_false_no_name" {
  command = plan

  variables {
    create_resource_group = false
    resource_group_name   = null
  }

  expect_failures = [var.create_resource_group]
}

# -----------------------------------------------------------------------
# Test 7: validator_log_retention_below_min — log_retention_days = 7.
# -----------------------------------------------------------------------
run "validator_log_retention_below_min" {
  command = plan

  variables {
    log_retention_days = 7
  }

  override_data {
    target = data.azurerm_resource_group.this[0]
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management"
      location = "germanywestcentral"
      name     = "rg-mgm-prod-gwc-management"
    }
  }

  expect_failures = [var.log_retention_days]
}

# -----------------------------------------------------------------------
# Test 8: validator_log_retention_above_max — log_retention_days = 5000.
# -----------------------------------------------------------------------
run "validator_log_retention_above_max" {
  command = plan

  variables {
    log_retention_days = 5000
  }

  override_data {
    target = data.azurerm_resource_group.this[0]
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management"
      location = "germanywestcentral"
      name     = "rg-mgm-prod-gwc-management"
    }
  }

  expect_failures = [var.log_retention_days]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_lock_kind — "Bogus" must fail.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    resource_group_name = "rg-mgm-prod-gwc-management"
    lock                = { kind = "Bogus" }
  }

  override_data {
    target = data.azurerm_resource_group.this[0]
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management"
      location = "germanywestcentral"
      name     = "rg-mgm-prod-gwc-management"
    }
  }

  expect_failures = [var.lock]
}
