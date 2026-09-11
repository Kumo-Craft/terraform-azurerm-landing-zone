# Plan-time tests for the AlertProcessingRule module.
#
# Run with:
#   cd modules/AlertProcessingRule
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  resource_group_name  = "rg-mgm-prod-gwc-monitoring"

  scopes               = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  add_action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.Insights/actionGroups/ag-platform"]
}

# 1. convention naming
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_monitor_alert_processing_rule_action_group.this.name == "apr-mgm-prod-gwc-01"
    error_message = "Name must follow apr-{sub}-{env}-{region}-{workload}."
  }
  assert {
    condition     = azurerm_monitor_alert_processing_rule_action_group.this.enabled == true
    error_message = "enabled must default to true."
  }
}

# 2. explicit name override
run "happy_name_override" {
  command = plan

  variables {
    name = "apr-legacy-custom"
  }

  assert {
    condition     = azurerm_monitor_alert_processing_rule_action_group.this.name == "apr-legacy-custom"
    error_message = "name override must wire through."
  }
}

# 3. subscription scope
run "happy_subscription_scope" {
  command = plan

  assert {
    condition     = azurerm_monitor_alert_processing_rule_action_group.this.scopes == var.scopes
    error_message = "Subscription scope must wire through."
  }
  assert {
    condition     = azurerm_monitor_alert_processing_rule_action_group.this.add_action_group_ids == var.add_action_group_ids
    error_message = "add_action_group_ids must wire through."
  }
}

# 4. multi-resource scope
run "happy_multi_resource_scope" {
  command = plan

  variables {
    scopes = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-a/providers/Microsoft.Compute/virtualMachines/vm-a",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-b",
    ]
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_action_group.this.scopes) == 2
    error_message = "Multiple scopes must be honoured."
  }
}

# 5. with lock
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

# 6. with condition (volume lever) — severity filter emitted
run "happy_with_condition" {
  command = plan

  variables {
    condition = {
      severity = { operator = "Equals", values = ["Sev0", "Sev1"] }
    }
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_action_group.this.condition) == 1
    error_message = "condition block must be emitted when var.condition is set."
  }
  assert {
    condition     = azurerm_monitor_alert_processing_rule_action_group.this.condition[0].severity[0].operator == "Equals"
    error_message = "condition.severity.operator must wire through."
  }
}

# 7. no condition by default => match all (no condition block)
run "happy_no_condition_default" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_action_group.this.condition) == 0
    error_message = "No condition block must be emitted by default (route all alerts)."
  }
}

# 8. empty add_action_group_ids => failure
run "validator_empty_action_groups" {
  command = plan

  variables {
    add_action_group_ids = []
  }

  expect_failures = [var.add_action_group_ids]
}

# 9. malformed action group id => failure
run "validator_malformed_action_group_id" {
  command = plan

  variables {
    add_action_group_ids = ["/subscriptions/x/resourceGroups/y/providers/Microsoft.Compute/virtualMachines/not-an-ag"]
  }

  expect_failures = [var.add_action_group_ids]
}

# 10. empty scopes => failure
run "validator_empty_scopes" {
  command = plan

  variables {
    scopes = []
  }

  expect_failures = [var.scopes]
}

# 11. invalid condition operator => failure
run "validator_invalid_condition_operator" {
  command = plan

  variables {
    condition = {
      severity = { operator = "Bogus", values = ["Sev0"] }
    }
  }

  expect_failures = [var.condition]
}

# 11b. empty condition object (all sub-blocks null) => failure
run "validator_condition_empty" {
  command = plan

  variables {
    condition = {}
  }

  expect_failures = [var.condition]
}

# 11c. restricted-operator field with a 4-value operator => failure
# (severity only supports Equals/NotEquals per ARM API).
run "validator_condition_restricted_operator" {
  command = plan

  variables {
    condition = {
      severity = { operator = "Contains", values = ["Sev0"] }
    }
  }

  expect_failures = [var.condition]
}

# 11d. scopes spanning two subscriptions => failure (APR is single-subscription).
run "validator_scopes_multi_subscription" {
  command = plan

  variables {
    scopes = [
      "/subscriptions/00000000-0000-0000-0000-000000000000",
      "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-x",
    ]
  }

  expect_failures = [var.scopes]
}

# 12. naming XOR failure
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}
