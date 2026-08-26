# Plan-time tests for the ApplicationInsights module.
#
# Mocks azurerm. Covers:
#   1. happy_default_naming          — convention naming, workspace-based defaults
#   2. happy_name_override           — explicit var.name (XOR escape hatch)
#   3. happy_local_auth_disabled     — disable var maps to local_authentication_enabled=false
#   4. happy_with_lock_and_rbac      — var.lock + 1 role_assignment
#   5. validator_naming_xor_fails    — name=null + all naming vars=null → failure
#   6. validator_invalid_workspace_id — non-LA-workspace ID → failure
#   7. validator_invalid_retention   — 45 days → failure
#   8. validator_invalid_app_type    — bad application_type → failure
#   9. validator_invalid_lock_kind   — lock.kind = "Bogus" → failure
#  10. validator_invalid_role_principal — principal_type = "Foo" → failure
#
# Run with:
#   cd modules/ApplicationInsights
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-sre"
  workspace_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-frc-sre/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-frc-sre"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, workspace-based defaults.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_application_insights.this.name == "appi-mgm-prod-frc-01"
    error_message = "AI name must follow the appi-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azurerm_application_insights.this.application_type == "web"
    error_message = "application_type must default to web."
  }

  assert {
    condition     = azurerm_application_insights.this.workspace_id == var.workspace_id
    error_message = "workspace_id must wire through (workspace-based AI)."
  }

  assert {
    condition     = azurerm_application_insights.this.retention_in_days == 90
    error_message = "retention_in_days must default to 90."
  }

  assert {
    condition     = azurerm_application_insights.this.internet_ingestion_enabled == true && azurerm_application_insights.this.internet_query_enabled == true
    error_message = "internet_ingestion/query must default to true."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "appi-legacy-custom"
  }

  assert {
    condition     = azurerm_application_insights.this.name == "appi-legacy-custom"
    error_message = "AI name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_local_auth_disabled — disable var maps to the non-deprecated
# local_authentication_enabled attribute (negated).
# -----------------------------------------------------------------------
run "happy_local_auth_disabled" {
  command = plan

  variables {
    local_authentication_disabled = true
  }

  assert {
    condition     = azurerm_application_insights.this.local_authentication_enabled == false
    error_message = "local_authentication_disabled=true must set local_authentication_enabled=false."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_lock_and_rbac — lock + 1 role assignment.
# -----------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      "monitoring-reader" = {
        role_definition_id_or_name = "Monitoring Reader"
        principal_id               = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One rbac module instance must be planned when 1 role assignment is supplied."
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_naming_xor_fails — name=null + naming vars=null → failure.
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
# Test 6: validator_invalid_workspace_id — non-LA-workspace ID → failure.
# -----------------------------------------------------------------------
run "validator_invalid_workspace_id" {
  command = plan

  variables {
    workspace_id = "/subscriptions/x/resourceGroups/y/providers/Microsoft.Insights/components/appi-x"
  }

  expect_failures = [var.workspace_id]
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_retention — 45 days → failure.
# -----------------------------------------------------------------------
run "validator_invalid_retention" {
  command = plan

  variables {
    retention_in_days = 45
  }

  expect_failures = [var.retention_in_days]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_app_type — bad application_type → failure.
# -----------------------------------------------------------------------
run "validator_invalid_app_type" {
  command = plan

  variables {
    application_type = "bogus"
  }

  expect_failures = [var.application_type]
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
# Test 10: validator_invalid_role_principal_type — "Foo" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    role_assignments = {
      "bad-entry" = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "Foo"
      }
    }
  }

  expect_failures = [var.role_assignments]
}
