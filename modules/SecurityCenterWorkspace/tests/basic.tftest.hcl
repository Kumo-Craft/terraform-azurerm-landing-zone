# Plan-time tests for the SecurityCenterWorkspace module.
#
# Mocks azurerm. Covers:
#   1. happy_bare_guid              — subscription_id = bare GUID, local.scope prefixed to /subscriptions/...
#   2. happy_full_subscription_path — subscription_id = full /subscriptions/<guid>, local.scope unchanged
#   3. happy_default_naming         — minimal valid inputs, resource planned
#   4. validator_invalid_law_id     — log_analytics_workspace_id not a valid ARM ID → regex failure
#   5. validator_invalid_subscription_id — subscription_id not a GUID → regex failure
#
# Run with:
#   cd modules/SecurityCenterWorkspace
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs reused across runs.
variables {
  subscription_id            = "00000000-0000-0000-0000-000000000001"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
}

# -----------------------------------------------------------------------
# Test 1: happy_bare_guid — bare GUID is normalized to full /subscriptions/... path.
# -----------------------------------------------------------------------
run "happy_bare_guid" {
  command = plan

  assert {
    condition     = azurerm_security_center_workspace.this.scope == "/subscriptions/00000000-0000-0000-0000-000000000001"
    error_message = "local.scope must prefix bare GUID with /subscriptions/."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_full_subscription_path — already-prefixed path must pass through unchanged.
# -----------------------------------------------------------------------
run "happy_full_subscription_path" {
  command = plan

  variables {
    subscription_id = "/subscriptions/00000000-0000-0000-0000-000000000001"
  }

  assert {
    condition     = azurerm_security_center_workspace.this.scope == "/subscriptions/00000000-0000-0000-0000-000000000001"
    error_message = "local.scope must leave an already-prefixed /subscriptions/<guid> unchanged."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_default_naming — minimal valid inputs, resource is planned.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_security_center_workspace.this.workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"
    error_message = "workspace_id must equal var.log_analytics_workspace_id."
  }
}

# -----------------------------------------------------------------------
# Test 4: validator_invalid_law_id — not a valid LAW ARM ID → LAW regex validator failure.
# -----------------------------------------------------------------------
run "validator_invalid_law_id" {
  command = plan

  variables {
    log_analytics_workspace_id = "not-a-valid-arm-id"
  }

  expect_failures = [var.log_analytics_workspace_id]
}

# -----------------------------------------------------------------------
# Test 5: validator_invalid_subscription_id — not a GUID → GUID regex validator failure.
# -----------------------------------------------------------------------
run "validator_invalid_subscription_id" {
  command = plan

  variables {
    subscription_id = "not-a-guid"
  }

  expect_failures = [var.subscription_id]
}
