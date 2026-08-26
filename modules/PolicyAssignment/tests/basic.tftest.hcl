# Plan-time tests for PolicyAssignment.

mock_provider "azurerm" {}

# ─── Happy paths ───────────────────────────────────────────────────────────────

# Test 1 — Subscription-scoped assignment
run "happy_subscription_scope" {
  command = plan
  variables {
    assignments = {
      "deny-public-storage" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Deny public storage"
        description          = "Denies storage accounts with public network access enabled."
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Expected one subscription-scoped policy assignment to be planned."
  }
  assert {
    condition     = length(azurerm_resource_group_policy_assignment.this) == 0
    error_message = "Expected zero RG-scoped policy assignments to be planned."
  }
  assert {
    condition     = length(azurerm_management_group_policy_assignment.this) == 0
    error_message = "Expected zero MG-scoped policy assignments to be planned."
  }
}

# Test 2 — Management Group-scoped assignment
run "happy_management_group_scope" {
  command = plan
  variables {
    assignments = {
      "audit-untagged" = {
        management_group_id  = "/providers/Microsoft.Management/managementGroups/platform"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/0a914e76-4921-4c19-b460-a2d36003525a"
        display_name         = "Audit resources without tags"
        description          = "Audits resources that do not have required tags."
      }
    }
  }
  assert {
    condition     = length(azurerm_management_group_policy_assignment.this) == 1
    error_message = "Expected one MG-scoped policy assignment to be planned."
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 0
    error_message = "Expected zero subscription-scoped policy assignments to be planned."
  }
  assert {
    condition     = length(azurerm_resource_group_policy_assignment.this) == 0
    error_message = "Expected zero RG-scoped policy assignments to be planned."
  }
}

# Test 3 — Resource Group-scoped assignment
run "happy_resource_group_scope" {
  command = plan
  variables {
    assignments = {
      "deny-vm-creation" = {
        resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
        display_name         = "Deny VM creation in RG"
        description          = "Denies creation of virtual machines in this resource group."
      }
    }
  }
  assert {
    condition     = length(azurerm_resource_group_policy_assignment.this) == 1
    error_message = "Expected one RG-scoped policy assignment to be planned."
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 0
    error_message = "Expected zero subscription-scoped policy assignments to be planned."
  }
  assert {
    condition     = length(azurerm_management_group_policy_assignment.this) == 0
    error_message = "Expected zero MG-scoped policy assignments to be planned."
  }
}

# Test 4 — enforce defaults to true (DoEnforce)
run "happy_enforce_default" {
  command = plan
  variables {
    assignments = {
      "audit-sql-tde" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/17k78e20-9358-41c9-923c-fb736d382a12"
        display_name         = "Audit SQL TDE"
        description          = "Audits SQL databases without TDE enabled."
      }
    }
  }
  assert {
    condition     = azurerm_subscription_policy_assignment.this["audit-sql-tde"].enforce == true
    error_message = "enforce should default to true."
  }
}

# Test 5 — Passing policy parameters
run "happy_with_parameters" {
  command = plan
  variables {
    assignments = {
      "audit-allowed-locations" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        display_name         = "Allowed locations"
        description          = "Restricts deployments to allowed Azure regions."
        parameters = {
          listOfAllowedLocations = ["westeurope", "northeurope"]
        }
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Expected one subscription-scoped assignment with parameters."
  }
  assert {
    condition     = azurerm_subscription_policy_assignment.this["audit-allowed-locations"].parameters != null
    error_message = "parameters should be set on the resource."
  }
}

# Test 6 — SystemAssigned identity (for DINE/Modify effects)
run "happy_with_identity" {
  command = plan
  variables {
    assignments = {
      "dine-diagnostics" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9"
        display_name         = "Deploy diagnostic settings"
        description          = "Deploys diagnostic settings for activity logs to a Log Analytics workspace."
        identity_type        = "SystemAssigned"
        location             = "westeurope"
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Expected one subscription-scoped assignment with a managed identity."
  }
  assert {
    condition     = azurerm_subscription_policy_assignment.this["dine-diagnostics"].location == "westeurope"
    error_message = "location should be wired through to the resource."
  }
}

# Test 7 — Mixed scopes: one sub + one MG in the same call
run "happy_mixed_scopes" {
  command = plan
  variables {
    assignments = {
      "sub-audit" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/0a914e76-4921-4c19-b460-a2d36003525a"
        display_name         = "Sub-level audit"
        description          = "Audits at subscription level."
      }
      "mg-deny" = {
        management_group_id  = "/providers/Microsoft.Management/managementGroups/corp"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "MG-level deny"
        description          = "Denies at management group level."
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Expected one subscription-scoped assignment."
  }
  assert {
    condition     = length(azurerm_management_group_policy_assignment.this) == 1
    error_message = "Expected one MG-scoped assignment."
  }
}

# ─── Validator expect_failures ─────────────────────────────────────────────────

# Test 8 — No scope set fails
run "validator_no_scope_fails" {
  command = plan
  variables {
    assignments = {
      "no-scope" = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Missing scope"
        description          = "This assignment has no scope set."
      }
    }
  }
  expect_failures = [var.assignments]
}

# Test 9 — Two scopes set simultaneously fails
run "validator_multiple_scopes_fail" {
  command = plan
  variables {
    assignments = {
      "two-scopes" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        management_group_id  = "/providers/Microsoft.Management/managementGroups/platform"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Two scopes"
        description          = "Invalid: both subscription_id and management_group_id set."
      }
    }
  }
  expect_failures = [var.assignments]
}

# Test 10 — Name exceeds 64 characters fails
run "validator_name_too_long" {
  command = plan
  variables {
    assignments = {
      "this-assignment-name-is-way-too-long-and-exceeds-the-azure-64-char-limit-x" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Too long name"
        description          = "Assignment name exceeds the 64-character limit."
      }
    }
  }
  expect_failures = [var.assignments]
}

# Test 11 — Invalid management_group_id format fails
run "validator_invalid_management_group_id" {
  command = plan
  variables {
    assignments = {
      "bad-mg-id" = {
        management_group_id  = "not-a-valid-mg-id"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Bad MG ID"
        description          = "Invalid management_group_id format."
      }
    }
  }
  expect_failures = [var.assignments]
}

# Test 12 — Invalid subscription_id format fails
run "validator_invalid_subscription_id" {
  command = plan
  variables {
    assignments = {
      "bad-sub-id" = {
        subscription_id      = "not-a-valid-subscription-id"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Bad subscription ID"
        description          = "Invalid subscription_id format."
      }
    }
  }
  expect_failures = [var.assignments]
}

# Test 13 — identity_type set without location fails
run "validator_identity_type_without_location" {
  command = plan
  variables {
    assignments = {
      "identity-no-location" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7433c107-6db4-4ad1-b57a-a76dce0154a1"
        display_name         = "Identity without location"
        description          = "identity_type set but location is missing."
        identity_type        = "SystemAssigned"
      }
    }
  }
  expect_failures = [var.assignments]
}

# ─── Cat 5 #12: auto_derive_roles_from_definition tests ───────────────────────

# Test 14 — auto_derive_roles_from_definition defaults to false (non-breaking)
# Verifies no data source is invoked and behavior is identical to before.
run "happy_auto_derive_default_off" {
  command = plan
  variables {
    assignments = {
      "dine-no-derive" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9"
        display_name         = "Deploy diagnostic settings (no auto-derive)"
        description          = "DINE assignment with auto_derive_roles_from_definition omitted (defaults false)."
        identity_type        = "SystemAssigned"
        location             = "westeurope"
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Expected one subscription-scoped assignment."
  }
  assert {
    condition     = length(data.azurerm_policy_definition.derived) == 0
    error_message = "data.azurerm_policy_definition.derived must be empty when auto_derive_roles_from_definition is false."
  }
}

# Test 15 — explicit role_assignments still work normally when auto_derive is off
run "happy_explicit_roles_unaffected" {
  command = plan
  variables {
    assignments = {
      "dine-explicit" = {
        subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9"
        display_name         = "DINE with explicit role"
        description          = "Explicit role_assignments work regardless of auto_derive_roles_from_definition."
        identity_type        = "SystemAssigned"
        location             = "westeurope"
        role_assignments = [{
          scope              = "/subscriptions/00000000-0000-0000-0000-000000000000"
          role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
        }]
      }
    }
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.this) == 1
    error_message = "Expected one subscription-scoped assignment."
  }
  assert {
    condition     = length(module.policy_identity) == 1
    error_message = "Expected one explicit role assignment when auto_derive is off."
  }
  assert {
    condition     = length(data.azurerm_policy_definition.derived) == 0
    error_message = "data.azurerm_policy_definition.derived must be empty when auto_derive_roles_from_definition is false."
  }
}

# Test 16 — auto_derive_roles_from_definition = true: derived roles are merged
# Uses override_data to mock the data source response (plan-time, no Azure calls).
run "happy_auto_derive_on_merges_roles" {
  command = plan

  # Mock the policy definition data source to return two role IDs
  # (simulates what a real DINE built-in like "Deploy Log Analytics agent"
  # returns in metadata.roleDefinitionIds).
  override_data {
    target = data.azurerm_policy_definition.derived["dine-auto"]
    values = {
      role_definition_ids = [
        "/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293",
        "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa",
      ]
    }
  }

  variables {
    assignments = {
      "dine-auto" = {
        subscription_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id              = "/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9"
        display_name                      = "DINE auto-derive roles"
        description                       = "Tests that role_definition_ids from the policy definition are merged as role assignments."
        identity_type                     = "SystemAssigned"
        location                          = "westeurope"
        auto_derive_roles_from_definition = true
      }
    }
  }
  assert {
    condition     = length(data.azurerm_policy_definition.derived) == 1
    error_message = "Expected exactly one policy definition data source call when auto_derive = true."
  }
  assert {
    condition     = length(module.policy_identity) == 2
    error_message = "Expected 2 derived role assignments (one per roleDefinitionId returned by the mocked data source)."
  }
}
