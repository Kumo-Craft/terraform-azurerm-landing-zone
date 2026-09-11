# Plan-time tests for the LogAnalyticsWorkspaceTable module.
#
# Run with:
#   cd modules/LogAnalyticsWorkspaceTable
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

variables {
  workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pgs-prod-gwc-management/providers/Microsoft.OperationalInsights/workspaces/log-pgs-prod-gwc-01"
}

# 1. Basic plan on the AKS audit tables (the cost use case).
run "happy_basic_plan" {
  command = plan

  variables {
    tables = {
      AKSAuditAdmin   = { plan = "Basic" }
      AKSControlPlane = { plan = "Basic" }
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace_table.this["AKSAuditAdmin"].plan == "Basic"
    error_message = "AKSAuditAdmin must be planned as Basic."
  }
  assert {
    condition     = length(azurerm_log_analytics_workspace_table.this) == 2
    error_message = "Both tables must be planned."
  }
}

# 2. Analytics plan with custom retention.
run "happy_analytics_retention" {
  command = plan

  variables {
    tables = {
      AppTraces = { plan = "Analytics", retention_in_days = 30, total_retention_in_days = 365 }
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace_table.this["AppTraces"].retention_in_days == 30
    error_message = "retention_in_days must wire through for Analytics tables."
  }
}

# 3. empty map is a no-op.
run "happy_empty" {
  command = plan

  assert {
    condition     = length(azurerm_log_analytics_workspace_table.this) == 0
    error_message = "No tables must be planned when tables = {}."
  }
}

# 4. invalid plan rejected.
run "validator_invalid_plan" {
  command = plan

  variables {
    tables = { AKSAuditAdmin = { plan = "Cheap" } }
  }

  expect_failures = [var.tables]
}

# 5. retention_in_days on a Basic table rejected.
run "validator_basic_retention" {
  command = plan

  variables {
    tables = { AKSAuditAdmin = { plan = "Basic", retention_in_days = 30 } }
  }

  expect_failures = [var.tables]
}

# 6. invalid workspace_id rejected.
run "validator_invalid_workspace_id" {
  command = plan

  variables {
    workspace_id = "/subscriptions/x/resourceGroups/y/providers/Microsoft.Foo/bar/baz"
  }

  expect_failures = [var.workspace_id]
}
