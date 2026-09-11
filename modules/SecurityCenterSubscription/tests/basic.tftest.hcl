# Plan-time tests for the SecurityCenterSubscription module (azapi rewrite).
#
# Run with:
#   cd modules/SecurityCenterSubscription
#   terraform init -backend=false
#   terraform test

mock_provider "azapi" {}
# azurerm is mocked only so the `removed` block (referencing the former
# azurerm_security_center_contact type) resolves; no azurerm resource is created.
mock_provider "azurerm" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  email           = "soc@example.com"
}

# 1. nominal — name "default", subscription normalized to parent_id, no sources declared.
run "happy_default" {
  command = plan

  assert {
    condition     = azapi_resource.this.name == "default"
    error_message = "name must be hardcoded 'default'."
  }
  assert {
    condition     = azapi_resource.this.type == "Microsoft.Security/securityContacts@2023-12-01-preview"
    error_message = "resource type must target the 2023-12-01-preview securityContacts API."
  }
  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "bare GUID subscription_id must normalize to the /subscriptions/<guid> parent_id."
  }
  assert {
    condition     = length(output.notifications_sources) == 0
    error_message = "notifications_sources null must produce no sources (preserve current — nothing imposed)."
  }
}

# 2. subscription_id as a full path — normalized (idempotent) into parent_id.
run "happy_subscription_id_path" {
  command = plan

  variables {
    subscription_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "path-form subscription_id must be used as parent_id unchanged."
  }
}

# 3. Alert + AttackPath — the ALZ-compliant posture that makes Deploy-ASC-SecurityContacts pass.
run "happy_alert_and_attackpath" {
  command = plan

  variables {
    notifications_sources = {
      alert       = { minimal_severity = "High" }
      attack_path = { minimal_risk_level = "Critical" }
    }
  }

  assert {
    condition     = length(output.notifications_sources) == 2
    error_message = "both Alert and AttackPath sources must be emitted."
  }
  assert {
    condition     = one([for s in output.notifications_sources : s.minimalSeverity if s.sourceType == "Alert"]) == "High"
    error_message = "Alert.minimalSeverity must wire through."
  }
  assert {
    condition     = one([for s in output.notifications_sources : s.minimalRiskLevel if s.sourceType == "AttackPath"]) == "Critical"
    error_message = "AttackPath.minimalRiskLevel must wire through."
  }
  # Regression guard: lock the CLEAN JSON shape — no cross-populated null keys.
  # concat() unifies to list(map(string)) (both values are strings), so each element
  # carries only its own key. If a future edit reintroduces null-padding, the extra
  # keys would appear here and fail this assertion. (jsonencode sorts keys.)
  assert {
    condition     = jsonencode(output.notifications_sources) == "[{\"minimalSeverity\":\"High\",\"sourceType\":\"Alert\"},{\"minimalRiskLevel\":\"Critical\",\"sourceType\":\"AttackPath\"}]"
    error_message = "notificationsSources JSON must be clean (no null-leaked keys)."
  }
}

# 4. Alert only — defaults minimal_severity to High.
run "happy_alert_only" {
  command = plan

  variables {
    notifications_sources = { alert = {} }
  }

  assert {
    condition     = length(output.notifications_sources) == 1
    error_message = "only the Alert source must be emitted."
  }
  assert {
    condition     = one([for s in output.notifications_sources : s.sourceType]) == "Alert"
    error_message = "the single source must be of type Alert."
  }
  assert {
    condition     = one([for s in output.notifications_sources : s.minimalSeverity]) == "High"
    error_message = "alert.minimal_severity must default to High."
  }
}

# 5. multi-recipient email (Azure allows ';'/','-separated) — accepted.
run "happy_multi_email" {
  command = plan

  variables {
    email = "soc@example.com; ciso@example.com"
  }

  assert {
    condition     = output.email == "soc@example.com; ciso@example.com"
    error_message = "multi-recipient email must be accepted and exposed."
  }
}

# 6. notifications_sources set but empty ({}) => at-least-one validator failure.
run "validator_sources_empty" {
  command = plan

  variables {
    notifications_sources = {}
  }

  expect_failures = [var.notifications_sources]
}

# 7. invalid Alert severity (Critical is AttackPath-only) => failure.
run "validator_bad_alert_severity" {
  command = plan

  variables {
    notifications_sources = { alert = { minimal_severity = "Critical" } }
  }

  expect_failures = [var.notifications_sources]
}

# 8. invalid AttackPath risk level => failure.
run "validator_bad_attackpath_risk" {
  command = plan

  variables {
    notifications_sources = { attack_path = { minimal_risk_level = "Extreme" } }
  }

  expect_failures = [var.notifications_sources]
}

# 9. non-GUID subscription_id => failure.
run "validator_bad_subscription_id" {
  command = plan

  variables {
    subscription_id = "not-a-guid"
  }

  expect_failures = [var.subscription_id]
}

# 10. invalid notifications_by_role.state => failure.
run "validator_bad_role_state" {
  command = plan

  variables {
    notifications_by_role = { state = "Enabled" }
  }

  expect_failures = [var.notifications_by_role]
}

# 11. invalid notifications_by_role.roles => failure.
run "validator_bad_role" {
  command = plan

  variables {
    notifications_by_role = { roles = ["SuperAdmin"] }
  }

  expect_failures = [var.notifications_by_role]
}

# 12. malformed email => failure.
run "validator_malformed_email" {
  command = plan

  variables {
    email = "not-an-email"
  }

  expect_failures = [var.email]
}
