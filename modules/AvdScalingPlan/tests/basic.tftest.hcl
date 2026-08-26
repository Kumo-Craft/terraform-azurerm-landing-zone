# Plan-time tests for the AvdScalingPlan module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming                    — convention naming, 1 minimal schedule (no ramp_up_*_percent), no associations, no lock, no rbac
#   2. happy_name_override                     — explicit var.name, assert XOR escape hatch
#   3. happy_with_host_pool_associations       — 2 host pool associations, 2 host_pool blocks planned
#   4. happy_with_lock_and_rbac               — lock + 1 role_assignment, both module blocks instantiated
#   5. happy_optional_ramp_up_percent_omitted  — F-10: schedule without ramp_up_*_percent plans cleanly
#   6. validator_empty_schedules_fails         — schedules = {} → F-11 failure
#   7. validator_invalid_load_balancing_algorithm — ramp_up_load_balancing_algorithm = "Foo" → failure
#   8. validator_invalid_stop_hosts_when       — ramp_down_stop_hosts_when = "Bar" → failure
#   9. validator_invalid_day_of_week           — days_of_week = ["monday"] (lowercase) → failure
#  10. validator_invalid_hh_mm                 — ramp_up_start_time = "25:00" → failure
#
# Run with:
#   cd modules/AvdScalingPlan
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  location            = "westeurope"
  resource_group_name = "rg-avd-nprd-weu-avd"
}

# ---------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, minimal schedule.
# ---------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "pooled"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  assert {
    condition     = length(module.naming) == 1
    error_message = "Naming module must be instantiated when var.name is null."
  }

  assert {
    condition     = azurerm_virtual_desktop_scaling_plan.this.location == "westeurope"
    error_message = "Location must be wired through."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "vdscaling-custom"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  assert {
    condition     = azurerm_virtual_desktop_scaling_plan.this.name == "vdscaling-custom"
    error_message = "Name override must produce the explicit name."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must not be instantiated when var.name is provided."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_with_host_pool_associations — 2 associations, 2 host_pool blocks.
# ---------------------------------------------------------------------
run "happy_with_host_pool_associations" {
  command = plan

  variables {
    name = "vdscaling-assoc"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {
      pool1 = {
        hostpool_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-avd-nprd-weu-pool1"
        scaling_plan_enabled = true
      }
      pool2 = {
        hostpool_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-avd-nprd-weu-pool2"
        scaling_plan_enabled = false
      }
    }
  }

  assert {
    condition     = length(azurerm_virtual_desktop_scaling_plan.this.host_pool) == 2
    error_message = "Two host_pool blocks must be planned when two associations are given."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_with_lock_and_rbac — lock + 1 role_assignment both planned.
# ---------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    name = "vdscaling-lock-rbac"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}

    lock = { kind = "CanNotDelete" }

    role_assignments = {
      avd_contributor = {
        role_definition_id_or_name = "Desktop Virtualization Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "RBAC module must have one instance when one role assignment is given."
  }

  assert {
    condition     = azurerm_virtual_desktop_scaling_plan.this.name == "vdscaling-lock-rbac"
    error_message = "Scaling plan name must match."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_optional_ramp_up_percent_omitted — F-10 verification.
#   ramp_up_minimum_hosts_percent + ramp_up_capacity_threshold_percent both omitted.
# ---------------------------------------------------------------------
run "happy_optional_ramp_up_percent_omitted" {
  command = plan

  variables {
    name = "vdscaling-no-rampup-pct"

    schedules = {
      weekday = {
        days_of_week                     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time               = "07:00"
        ramp_up_load_balancing_algorithm = "BreadthFirst"
        # ramp_up_minimum_hosts_percent omitted (optional after F-10)
        # ramp_up_capacity_threshold_percent omitted (optional after F-10)
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  assert {
    condition     = azurerm_virtual_desktop_scaling_plan.this.name == "vdscaling-no-rampup-pct"
    error_message = "Plan must succeed when ramp_up_*_percent fields are omitted."
  }
}

# ---------------------------------------------------------------------
# Test 6: validator_empty_schedules_fails — F-11 min-1-schedule guard.
# ---------------------------------------------------------------------
run "validator_empty_schedules_fails" {
  command = plan

  variables {
    name                   = "vdscaling-no-sched"
    schedules              = {}
    host_pool_associations = {}
  }

  expect_failures = [var.schedules]
}

# ---------------------------------------------------------------------
# Test 7: validator_invalid_load_balancing_algorithm — "Foo" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_load_balancing_algorithm" {
  command = plan

  variables {
    name = "vdscaling-bad-algo"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "Foo"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  expect_failures = [var.schedules]
}

# ---------------------------------------------------------------------
# Test 8: validator_invalid_stop_hosts_when — "Bar" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_stop_hosts_when" {
  command = plan

  variables {
    name = "vdscaling-bad-stop"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "Bar"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  expect_failures = [var.schedules]
}

# ---------------------------------------------------------------------
# Test 9: validator_invalid_day_of_week — lowercase "monday" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_day_of_week" {
  command = plan

  variables {
    name = "vdscaling-bad-day"

    schedules = {
      weekday = {
        days_of_week                         = ["monday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  expect_failures = [var.schedules]
}

# ---------------------------------------------------------------------
# Test 10: validator_invalid_hh_mm — "25:00" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_hh_mm" {
  command = plan

  variables {
    name = "vdscaling-bad-time"

    schedules = {
      weekday = {
        days_of_week                         = ["Monday"]
        ramp_up_start_time                   = "25:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "You will be logged off in 30 minutes."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }

    host_pool_associations = {}
  }

  expect_failures = [var.schedules]
}
