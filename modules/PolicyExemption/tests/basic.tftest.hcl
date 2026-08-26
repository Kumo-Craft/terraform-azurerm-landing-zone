# Plan-time tests for PolicyExemption.

mock_provider "azurerm" {}

# ─── Happy paths ───────────────────────────────────────────────────────────────

# Test 1 — Subscription-scoped exemption
run "happy_subscription_scope" {
  command = plan
  variables {
    exemptions = {
      "exempt-breakglass" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        display_name         = "Break-glass subscription exemption"
        description          = "Exempts break-glass subscription from storage deny assignment."
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_exemption.this) == 1
    error_message = "Expected one subscription-scoped policy exemption to be planned."
  }
  assert {
    condition     = length(azurerm_resource_group_policy_exemption.this) == 0
    error_message = "Expected zero RG-scoped policy exemptions to be planned."
  }
  assert {
    condition     = length(azurerm_management_group_policy_exemption.this) == 0
    error_message = "Expected zero MG-scoped policy exemptions to be planned."
  }
}

# Test 2 — Management Group-scoped exemption
run "happy_management_group_scope" {
  command = plan
  variables {
    exemptions = {
      "exempt-sandbox-mg" = {
        management_group_id  = "/providers/Microsoft.Management/managementGroups/sandbox"
        policy_assignment_id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyAssignments/audit-untagged"
        display_name         = "Sandbox MG exemption"
        description          = "Exempts sandbox management group from the tagging audit assignment."
      }
    }
  }
  assert {
    condition     = length(azurerm_management_group_policy_exemption.this) == 1
    error_message = "Expected one MG-scoped policy exemption to be planned."
  }
  assert {
    condition     = length(azurerm_subscription_policy_exemption.this) == 0
    error_message = "Expected zero subscription-scoped policy exemptions to be planned."
  }
  assert {
    condition     = length(azurerm_resource_group_policy_exemption.this) == 0
    error_message = "Expected zero RG-scoped policy exemptions to be planned."
  }
}

# Test 3 — Resource Group-scoped exemption
run "happy_resource_group_scope" {
  command = plan
  variables {
    exemptions = {
      "exempt-legacy-rg" = {
        resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-vm-creation"
        display_name         = "Legacy RG exemption"
        description          = "Exempts legacy resource group from the VM deny assignment."
      }
    }
  }
  assert {
    condition     = length(azurerm_resource_group_policy_exemption.this) == 1
    error_message = "Expected one RG-scoped policy exemption to be planned."
  }
  assert {
    condition     = length(azurerm_subscription_policy_exemption.this) == 0
    error_message = "Expected zero subscription-scoped policy exemptions to be planned."
  }
  assert {
    condition     = length(azurerm_management_group_policy_exemption.this) == 0
    error_message = "Expected zero MG-scoped policy exemptions to be planned."
  }
}

# Test 4 — Waiver category (accept risk)
run "happy_waiver_category" {
  command = plan
  variables {
    exemptions = {
      "waiver-legacy-app" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        exemption_category   = "Waiver"
        display_name         = "Legacy app waiver"
        description          = "Risk accepted for legacy app that cannot be migrated immediately."
      }
    }
  }
  assert {
    condition     = azurerm_subscription_policy_exemption.this["waiver-legacy-app"].exemption_category == "Waiver"
    error_message = "exemption_category should be Waiver."
  }
}

# Test 5 — Mitigated category (compensating control)
run "happy_mitigated_category" {
  command = plan
  variables {
    exemptions = {
      "mitigated-firewall" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        exemption_category   = "Mitigated"
        display_name         = "Firewall-mitigated exemption"
        description          = "Compensating control: Azure Firewall with IDPS enabled."
      }
    }
  }
  assert {
    condition     = azurerm_subscription_policy_exemption.this["mitigated-firewall"].exemption_category == "Mitigated"
    error_message = "exemption_category should be Mitigated."
  }
}

# Test 6 — expires_on wired through correctly
run "happy_with_expires_on" {
  command = plan
  variables {
    exemptions = {
      "time-limited-waiver" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        display_name         = "Time-limited waiver"
        description          = "Exemption expires after the migration window closes."
        expires_on           = "2027-12-31T23:59:00Z"
      }
    }
  }
  assert {
    condition     = azurerm_subscription_policy_exemption.this["time-limited-waiver"].expires_on == "2027-12-31T23:59:00Z"
    error_message = "expires_on should be wired through to the resource."
  }
}

# Test 7 — Targeted initiative exemption (policy_definition_reference_ids)
run "happy_targeted_initiative" {
  command = plan
  variables {
    exemptions = {
      "targeted-initiative" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/platform-baseline"
        display_name         = "Targeted initiative exemption"
        description          = "Exempts only specific child policies from the platform baseline initiative."
        policy_definition_reference_ids = [
          "deny-public-storage",
          "audit-untagged"
        ]
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_exemption.this) == 1
    error_message = "Expected one subscription-scoped exemption with targeted reference IDs."
  }
  assert {
    condition     = length(azurerm_subscription_policy_exemption.this["targeted-initiative"].policy_definition_reference_ids) == 2
    error_message = "policy_definition_reference_ids should contain exactly 2 entries."
  }
}

# ─── Validator expect_failures ─────────────────────────────────────────────────

# Test 8 — No scope set fails
run "validator_no_scope_fails" {
  command = plan
  variables {
    exemptions = {
      "no-scope" = {
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        display_name         = "Missing scope"
        description          = "This exemption has no scope set."
      }
    }
  }
  expect_failures = [var.exemptions]
}

# Test 9 — Two scopes set simultaneously fails
run "validator_multiple_scopes_fail" {
  command = plan
  variables {
    exemptions = {
      "two-scopes" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        management_group_id  = "/providers/Microsoft.Management/managementGroups/platform"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        display_name         = "Two scopes"
        description          = "Invalid: both subscription_id and management_group_id set."
      }
    }
  }
  expect_failures = [var.exemptions]
}

# Test 10 — Invalid exemption_category fails
run "validator_invalid_category" {
  command = plan
  variables {
    exemptions = {
      "bad-category" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        exemption_category   = "NotACategory"
        display_name         = "Bad category"
        description          = "Invalid exemption_category value."
      }
    }
  }
  expect_failures = [var.exemptions]
}

# Test 11 — Invalid expires_on format fails
run "validator_invalid_expires_on_format" {
  command = plan
  variables {
    exemptions = {
      "bad-expires-on" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        display_name         = "Bad expires_on"
        description          = "expires_on is not a valid RFC3339 UTC timestamp."
        expires_on           = "2027-12-31"
      }
    }
  }
  expect_failures = [var.exemptions]
}

# Test 12 — Name exceeds 64 characters fails
run "validator_name_too_long" {
  command = plan
  variables {
    exemptions = {
      "this-exemption-name-is-way-too-long-and-exceeds-the-azure-64-char-limit-xxx" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/deny-public-storage"
        display_name         = "Too long name"
        description          = "Exemption name exceeds the 64-character limit."
      }
    }
  }
  expect_failures = [var.exemptions]
}
