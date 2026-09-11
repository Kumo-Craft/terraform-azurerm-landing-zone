# Plan-time tests for the ActivityLogAlerts module.
#
# Run with:
#   cd modules/ActivityLogAlerts
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  subscription_acronym = "pgs"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "servicehealth"
  resource_group_name  = "rg-pgs-prod-gwc-monitoring"

  scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pgs-prod-gwc-monitoring/providers/Microsoft.Insights/actionGroups/ag-platform"]

  alerts = {
    incidents = {
      category       = "ServiceHealth"
      description    = "Azure service incidents"
      service_health = { events = ["Incident"] }
    }
  }
}

# 1. Service Health alert — convention name + location global + category wired.
run "happy_service_health" {
  command = plan

  assert {
    condition     = azurerm_monitor_activity_log_alert.this["incidents"].name == "ala-pgs-prod-gwc-servicehealth-incidents"
    error_message = "Name must be {base}-{key} = ala-pgs-prod-gwc-servicehealth-incidents."
  }
  assert {
    condition     = azurerm_monitor_activity_log_alert.this["incidents"].location == "global"
    error_message = "location must be hardcoded 'global' (activity log alert is a global resource)."
  }
  assert {
    condition     = azurerm_monitor_activity_log_alert.this["incidents"].criteria[0].category == "ServiceHealth"
    error_message = "criteria.category must wire through."
  }
  assert {
    condition     = length(azurerm_monitor_activity_log_alert.this["incidents"].action) == 1
    error_message = "The single action group must be attached."
  }
}

# 2. Two alerts in the map.
run "happy_two_alerts" {
  command = plan

  variables {
    alerts = {
      incidents   = { category = "ServiceHealth", service_health = { events = ["Incident"] } }
      maintenance = { category = "ServiceHealth", service_health = { events = ["Maintenance"] } }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.this) == 2
    error_message = "Two alerts must be planned."
  }
  assert {
    condition     = azurerm_monitor_activity_log_alert.this["maintenance"].location == "global"
    error_message = "Every alert must be global."
  }
}

# 3. explicit name override.
run "happy_name_override" {
  command = plan

  variables {
    name = "ala-custom"
  }

  assert {
    condition     = azurerm_monitor_activity_log_alert.this["incidents"].name == "ala-custom-incidents"
    error_message = "name override must be used as the base ({name}-{key})."
  }
}

# 4. resource_health alert (the immediate complement).
run "happy_resource_health" {
  command = plan

  variables {
    alerts = {
      rh = {
        category        = "ResourceHealth"
        resource_health = { current = ["Degraded", "Unavailable"] }
      }
    }
  }

  assert {
    condition     = azurerm_monitor_activity_log_alert.this["rh"].criteria[0].category == "ResourceHealth"
    error_message = "resource_health alert must wire ResourceHealth category."
  }
}

# 5. with lock (one per alert).
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "One lock entry must be planned per alert when var.lock is set."
  }
}

# 6. invalid category => failure.
run "validator_invalid_category" {
  command = plan

  variables {
    alerts = { bad = { category = "Bogus" } }
  }

  expect_failures = [var.alerts]
}

# 7. service_health with wrong category => failure.
run "validator_service_health_wrong_category" {
  command = plan

  variables {
    alerts = { bad = { category = "Administrative", service_health = { events = ["Incident"] } } }
  }

  expect_failures = [var.alerts]
}

# 8. malformed action group id => failure.
run "validator_malformed_action_group_id" {
  command = plan

  variables {
    action_group_ids = ["/subscriptions/x/resourceGroups/y/providers/Microsoft.Compute/virtualMachines/not-an-ag"]
  }

  expect_failures = [var.action_group_ids]
}

# 9. empty scopes => failure.
run "validator_empty_scopes" {
  command = plan

  variables {
    scopes = []
  }

  expect_failures = [var.scopes]
}

# 10. naming XOR failure.
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}
