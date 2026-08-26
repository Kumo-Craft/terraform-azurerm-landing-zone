# Plan-time tests for the ConsumptionBudget module.
#
# Mocks azurerm; the Naming submodule's random provider runs for real (offline).
#
# Covers:
#   1. happy_minimal      — derived name, amount, single notification
#   2. name_override      — var.name wins, Naming module not instantiated
#   3. notifications_multi— 3 notifications (Actual + Forecasted)
#   4. filter_dimension   — optional filter block emitted
#   5. with_lock          — optional lock scoped to the budget
#   6. validator_no_notifications  — empty list → fail
#   7. validator_notification_no_contact — no email/group/role → fail
#   8. validator_bad_start_date    — not first-of-month → fail
#   9. validator_bad_time_grain    — invalid grain → fail
#  10. validator_bad_rg_id         — not an RG ARM id → fail
#
# Run with:
#   cd modules/ConsumptionBudget
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs.
variables {
  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "platform"
  resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-gwc-platform"
  amount               = 1000
  start_date           = "2026-07-01T00:00:00Z"
  notifications = [
    {
      threshold      = 90
      threshold_type = "Actual"
      contact_emails = ["finops@example.com"]
    }
  ]
}

# -----------------------------------------------------------------------
# Test 1: happy_minimal — derived slug name + defaults.
# -----------------------------------------------------------------------
run "happy_minimal" {
  command = plan

  assert {
    condition     = azurerm_consumption_budget_resource_group.this.name == "bdg-con-prod-gwc-platform"
    error_message = "Budget name must derive as bdg-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_consumption_budget_resource_group.this.amount == 1000 && azurerm_consumption_budget_resource_group.this.time_grain == "Monthly"
    error_message = "amount/time_grain must pass through with the Monthly default."
  }

  assert {
    condition     = length(azurerm_consumption_budget_resource_group.this.notification) == 1
    error_message = "Exactly one notification block must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 2: name_override — escape hatch wins.
# -----------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name = "bdg-custom-name"
  }

  assert {
    condition     = azurerm_consumption_budget_resource_group.this.name == "bdg-custom-name"
    error_message = "var.name must override the derived name."
  }
}

# -----------------------------------------------------------------------
# Test 3: notifications_multi — Actual + Forecasted mix.
# -----------------------------------------------------------------------
run "notifications_multi" {
  command = plan

  variables {
    notifications = [
      { threshold = 80, threshold_type = "Actual", contact_emails = ["a@example.com"] },
      { threshold = 100, threshold_type = "Actual", contact_groups = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag"] },
      { threshold = 100, threshold_type = "Forecasted", operator = "GreaterThanOrEqualTo", contact_roles = ["Owner"] },
    ]
  }

  assert {
    condition     = length(azurerm_consumption_budget_resource_group.this.notification) == 3
    error_message = "Three notification blocks must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 4: filter_dimension — optional filter block emitted.
# -----------------------------------------------------------------------
run "filter_dimension" {
  command = plan

  variables {
    filter = {
      dimensions = [{ name = "ResourceType", values = ["microsoft.compute/virtualmachines"] }]
    }
  }

  assert {
    condition     = length(azurerm_consumption_budget_resource_group.this.filter) == 1
    error_message = "A filter block must be planned when var.filter is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: with_lock — optional lock scoped to the budget.
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
# Test 6: validator_no_notifications — empty list → fail.
# -----------------------------------------------------------------------
run "validator_no_notifications" {
  command = plan

  variables {
    notifications = []
  }

  expect_failures = [var.notifications]
}

# -----------------------------------------------------------------------
# Test 7: validator_notification_no_contact — no contacts → fail.
# -----------------------------------------------------------------------
run "validator_notification_no_contact" {
  command = plan

  variables {
    notifications = [{ threshold = 90 }]
  }

  expect_failures = [var.notifications]
}

# -----------------------------------------------------------------------
# Test 8: validator_bad_start_date — not first-of-month → fail.
# -----------------------------------------------------------------------
run "validator_bad_start_date" {
  command = plan

  variables {
    start_date = "2026-07-15T00:00:00Z"
  }

  expect_failures = [var.start_date]
}

# -----------------------------------------------------------------------
# Test 9: validator_bad_time_grain — invalid grain → fail.
# -----------------------------------------------------------------------
run "validator_bad_time_grain" {
  command = plan

  variables {
    time_grain = "Weekly"
  }

  expect_failures = [var.time_grain]
}

# -----------------------------------------------------------------------
# Test 10: validator_bad_rg_id — not an RG ARM id → fail.
# -----------------------------------------------------------------------
run "validator_bad_rg_id" {
  command = plan

  variables {
    resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.resource_group_id]
}
