# Plan-time tests for PolicySetDefinition.

mock_provider "azurerm" {}

# Test 1 — Happy path: subscription-scoped set with 2 members + 1 group
run "sub_scoped_with_group_happy" {
  command = plan
  variables {
    set_definitions = {
      "platform-baseline" = {
        display_name = "Platform Baseline"
        description  = "Platform-wide baseline policies for the landing zone."
        metadata     = { category = "General" }
        policy_definition_references = [
          {
            policy_definition_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/deny-public-storage"
            reference_id                  = "deny-public-storage"
            policy_definition_group_names = ["storage"]
          },
          {
            policy_definition_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/audit-untagged"
            reference_id                  = "audit-untagged"
            policy_definition_group_names = ["tagging"]
          }
        ]
        policy_definition_groups = [
          { name = "storage", display_name = "Storage Controls", category = "Storage" },
          { name = "tagging", display_name = "Tagging Controls", category = "Governance" }
        ]
      }
    }
  }
  assert {
    condition     = length(azurerm_policy_set_definition.this) == 1
    error_message = "Expected one subscription-scoped policy set definition to be planned."
  }
  assert {
    condition     = length(azurerm_management_group_policy_set_definition.this) == 0
    error_message = "Expected zero MG-scoped policy set definitions to be planned."
  }
}

# Test 2 — Happy path: MG-scoped set definition
run "mg_scoped_happy" {
  command = plan
  variables {
    set_definitions = {
      "corp-governance" = {
        display_name        = "Corp Governance Initiative"
        management_group_id = "/providers/Microsoft.Management/managementGroups/corp"
        policy_definition_references = [
          {
            policy_definition_id = "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyDefinitions/deny-nsg-any"
            reference_id         = "deny-nsg-any"
          }
        ]
      }
    }
  }
  assert {
    condition     = length(azurerm_management_group_policy_set_definition.this) == 1
    error_message = "Expected one MG-scoped policy set definition to be planned."
  }
  assert {
    condition     = length(azurerm_policy_set_definition.this) == 0
    error_message = "Expected zero subscription-scoped policy set definitions to be planned."
  }
}

# Test 3 — Happy path: mixed scopes (one sub + one MG) in a single call
run "mixed_scopes_happy" {
  command = plan
  variables {
    set_definitions = {
      "sub-baseline" = {
        display_name = "Subscription Baseline"
        policy_definition_references = [
          {
            policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/deny-pub"
            reference_id         = "deny-pub"
          }
        ]
      }
      "mg-baseline" = {
        display_name        = "MG Baseline"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        policy_definition_references = [
          {
            policy_definition_id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyDefinitions/audit-tags"
            reference_id         = "audit-tags"
          }
        ]
      }
    }
  }
  assert {
    condition     = length(azurerm_policy_set_definition.this) == 1
    error_message = "Expected one subscription-scoped policy set definition."
  }
  assert {
    condition     = length(azurerm_management_group_policy_set_definition.this) == 1
    error_message = "Expected one MG-scoped policy set definition."
  }
}

# Test 4 — Empty policy_definition_references fails validation
run "empty_references_fails" {
  command = plan
  variables {
    set_definitions = {
      "empty-set" = {
        display_name                 = "Empty Set"
        policy_definition_references = []
      }
    }
  }
  expect_failures = [var.set_definitions]
}

# Test 5 — Duplicate reference_id within a set fails validation
run "duplicate_reference_id_fails" {
  command = plan
  variables {
    set_definitions = {
      "dup-refs" = {
        display_name = "Duplicate Reference IDs"
        policy_definition_references = [
          {
            policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/def-a"
            reference_id         = "same-id"
          },
          {
            policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/def-b"
            reference_id         = "same-id"
          }
        ]
      }
    }
  }
  expect_failures = [var.set_definitions]
}

# Test 6 — Invalid policy_type fails validation
run "invalid_policy_type_fails" {
  command = plan
  variables {
    set_definitions = {
      "bad-type" = {
        display_name = "Bad Policy Type"
        policy_type  = "Wrong"
        policy_definition_references = [
          {
            policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/def-a"
          }
        ]
      }
    }
  }
  expect_failures = [var.set_definitions]
}

# Test 7 — Name length exceeds 64 characters fails validation
run "name_too_long_fails" {
  command = plan
  variables {
    set_definitions = {
      "this-set-definition-name-is-way-too-long-and-exceeds-the-azure-64-char-limit" = {
        display_name = "Too Long Name"
        policy_definition_references = [
          {
            policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/def-a"
          }
        ]
      }
    }
  }
  expect_failures = [var.set_definitions]
}
