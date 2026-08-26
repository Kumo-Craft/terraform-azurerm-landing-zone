# Plan-time tests for PolicyDefinition.

mock_provider "azurerm" {}

# Test 1 — Happy path: subscription-scoped definition (no management_group_id)
run "subscription_scoped_happy" {
  command = plan
  variables {
    definitions = {
      "deny-public-storage" = {
        display_name = "Deny public storage accounts"
        policy_rule = {
          if = {
            allOf = [
              { field = "type", equals = "Microsoft.Storage/storageAccounts" },
              { field = "Microsoft.Storage/storageAccounts/publicNetworkAccess", equals = "Enabled" }
            ]
          }
          then = { effect = "deny" }
        }
        description = "Prevents creation of storage accounts with public network access enabled."
        metadata    = { category = "Storage" }
      }
    }
  }
  assert {
    condition     = length(azurerm_policy_definition.this) == 1
    error_message = "Expected exactly one policy definition to be planned."
  }
}

# Test 2 — Happy path: MG-scoped definition
run "mg_scoped_happy" {
  command = plan
  variables {
    definitions = {
      "audit-untagged-resources" = {
        display_name        = "Audit untagged resources"
        management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
        policy_rule = {
          if   = { field = "tags", exists = "false" }
          then = { effect = "audit" }
        }
        parameters = {
          tagName = {
            type     = "String"
            metadata = { displayName = "Tag Name" }
          }
        }
      }
    }
  }
  assert {
    condition     = length(azurerm_policy_definition.this) == 1
    error_message = "Expected exactly one MG-scoped policy definition to be planned."
  }
}

# Test 3 — Happy path: multiple definitions in one call
run "multiple_definitions_happy" {
  command = plan
  variables {
    definitions = {
      "def-a" = {
        display_name = "Definition A"
        policy_rule  = { if = { field = "type", equals = "Microsoft.Compute/virtualMachines" }, then = { effect = "audit" } }
      }
      "def-b" = {
        display_name = "Definition B"
        policy_rule  = { if = { field = "type", equals = "Microsoft.Network/publicIPAddresses" }, then = { effect = "deny" } }
        mode         = "Indexed"
        policy_type  = "Custom"
      }
    }
  }
  assert {
    condition     = length(azurerm_policy_definition.this) == 2
    error_message = "Expected two policy definitions to be planned."
  }
}

# Test 4 — Invalid policy_type
run "invalid_policy_type_fails" {
  command = plan
  variables {
    definitions = {
      "bad-type" = {
        display_name = "Bad policy type"
        policy_rule  = { if = { field = "type", equals = "Microsoft.Compute/virtualMachines" }, then = { effect = "audit" } }
        policy_type  = "Wrong"
      }
    }
  }
  expect_failures = [var.definitions]
}

# Test 5 — Invalid mode
run "invalid_mode_fails" {
  command = plan
  variables {
    definitions = {
      "bad-mode" = {
        display_name = "Bad mode"
        policy_rule  = { if = { field = "type", equals = "Microsoft.Compute/virtualMachines" }, then = { effect = "audit" } }
        mode         = "BadMode"
      }
    }
  }
  expect_failures = [var.definitions]
}

# Test 6 — Name length exceeds 64 characters
run "name_too_long_fails" {
  command = plan
  variables {
    definitions = {
      "this-definition-name-is-way-too-long-and-exceeds-the-azure-64-char-limit-x" = {
        display_name = "Too long name"
        policy_rule  = { if = { field = "type", equals = "Microsoft.Compute/virtualMachines" }, then = { effect = "audit" } }
      }
    }
  }
  expect_failures = [var.definitions]
}

# Test 7 — Invalid management_group_id format
run "invalid_mg_id_fails" {
  command = plan
  variables {
    definitions = {
      "bad-mg" = {
        display_name        = "Bad MG ID"
        policy_rule         = { if = { field = "type", equals = "Microsoft.Compute/virtualMachines" }, then = { effect = "audit" } }
        management_group_id = "not-a-valid-mg-id"
      }
    }
  }
  expect_failures = [var.definitions]
}
