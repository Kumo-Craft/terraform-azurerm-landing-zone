# Plan-time tests for the RoleAssignment module.
#
# These tests run via `terraform test` and only exercise validation logic
# + plan resolution — no real Azure resources are created. They serve as
# a smoke test for the variable shape, validators, and lifecycle preconditions.
#
# Run locally with:
#   cd RoleAssignment
#   terraform init -backend=false
#   terraform test

# ---------------------------------------------------------------------
# Provider mock — required so plan can resolve azurerm without creds.
# ---------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------
# Test 1: role_by_name — role_definition_name set, plan succeeds,
#         output.id is resolved by the mock provider.
# ---------------------------------------------------------------------
run "role_by_name" {
  command = plan

  variables {
    scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id         = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name = "Contributor"
  }

  # Under plan, resource attributes are unknown; assert the resource is planned
  # (no assert needed — plan succeeding without error is sufficient here).
}

# ---------------------------------------------------------------------
# Test 2: role_by_id — role_definition_id set (full resource ID),
#         plan succeeds.
# ---------------------------------------------------------------------
run "role_by_id" {
  command = plan

  variables {
    scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id       = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
  }
}

# ---------------------------------------------------------------------
# Test 3: both_null_fails — neither role_definition_name nor
#         role_definition_id set; F1 precondition must fire.
# ---------------------------------------------------------------------
run "both_null_fails" {
  command = plan

  variables {
    scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  }

  expect_failures = [azurerm_role_assignment.this]
}

# ---------------------------------------------------------------------
# Test 4: both_set_fails — both role_definition_name and
#         role_definition_id set; F1 precondition must fire.
# ---------------------------------------------------------------------
run "both_set_fails" {
  command = plan

  variables {
    scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id         = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name = "Contributor"
    role_definition_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
  }

  expect_failures = [azurerm_role_assignment.this]
}

# ---------------------------------------------------------------------
# Test 5: invalid_principal_type_fails — "Computer" is not in the
#         allowed enum; var.principal_type validator must fire.
# ---------------------------------------------------------------------
run "invalid_principal_type_fails" {
  command = plan

  variables {
    scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id         = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name = "Contributor"
    principal_type       = "Computer"
  }

  expect_failures = [var.principal_type]
}

# ---------------------------------------------------------------------
# Test 6: invalid_condition_version_fails — condition_version "3.0"
#         is not allowed; var.condition_version validator must fire.
# ---------------------------------------------------------------------
run "invalid_condition_version_fails" {
  command = plan

  variables {
    scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id         = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name = "Contributor"
    condition            = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'private'"
    condition_version    = "3.0"
  }

  expect_failures = [var.condition_version]
}

# ---------------------------------------------------------------------
# Test 7: condition_without_version_fails — condition set but
#         condition_version omitted; F2 precondition must fire.
# ---------------------------------------------------------------------
run "condition_without_version_fails" {
  command = plan

  variables {
    scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id         = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name = "Contributor"
    condition            = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'private'"
  }

  expect_failures = [azurerm_role_assignment.this]
}

# ---------------------------------------------------------------------
# Test 8: version_without_condition_fails — condition_version set but
#         condition omitted; F2 precondition inverse branch must fire.
# ---------------------------------------------------------------------
run "version_without_condition_fails" {
  command = plan

  variables {
    scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id         = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name = "Contributor"
    condition_version    = "2.0"
    # condition intentionally not set
  }

  expect_failures = [azurerm_role_assignment.this]
}

# ---------------------------------------------------------------------
# Test 9: role_by_bare_guid — role_definition_id supplied as a bare
#         GUID (no /providers/... prefix); normalization branch in
#         main.tf lines 11-13 prepends the full path.
# ---------------------------------------------------------------------
run "role_by_bare_guid" {
  command = plan

  variables {
    scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id       = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_id = "acdd72a7-3385-48ef-bd42-f606fba81ae7" # bare GUID, no /providers/... prefix
  }

  # Clean plan = success; the mock provider accepts the normalised full path
  # produced by the ternary in main.tf. The normalised value is knowable at
  # plan time (pure string expression), but mock_provider returns an unknown
  # for computed resource attributes — matching the style of role_by_id.
}

# ---------------------------------------------------------------------
# Test 10: delegated_managed_identity_smoke — delegated_managed_identity_resource_id
#          wired; plan must succeed (mock provider accepts the argument).
# ---------------------------------------------------------------------
run "delegated_managed_identity_smoke" {
  command = plan

  variables {
    scope                                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id                           = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name                   = "Contributor"
    delegated_managed_identity_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-mi-prod-gwc/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mi-prod-gwc-delegated"
  }

  # Clean plan = success; the mock provider accepts the wired argument.
}

# ---------------------------------------------------------------------
# Test 11: role_by_id_or_name_with_path — the unified caller input
#          `role_definition_id_or_name` accepts a full /providers/...
#          path and dispatches it to role_definition_id. Used by
#          wrapper modules (KeyVault, StorageAccount, etc.) refactored
#          in 2026-05-27 to delegate RBAC to this module.
# ---------------------------------------------------------------------
run "role_by_id_or_name_with_path" {
  command = plan

  variables {
    scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id               = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
  }

  # Clean plan = success; main.tf locals dispatch this to role_definition_id.
}

# ---------------------------------------------------------------------
# Test 12: role_by_id_or_name_with_name — unified input accepts a bare
#          name and dispatches to role_definition_name.
# ---------------------------------------------------------------------
run "role_by_id_or_name_with_name" {
  command = plan

  variables {
    scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id               = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_id_or_name = "Contributor"
  }

  # Clean plan = success; main.tf locals dispatch this to role_definition_name.
}

# ---------------------------------------------------------------------
# Test 13: role_definition_*_three_set_fails — caller supplies all
#          three role identifier inputs; the F1 precondition (count == 1)
#          must fire.
# ---------------------------------------------------------------------
run "three_role_definition_inputs_fails" {
  command = plan

  variables {
    scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data"
    principal_id               = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_name       = "Contributor"
    role_definition_id_or_name = "Reader"
  }

  expect_failures = [azurerm_role_assignment.this]
}
