# Plan-time tests for the RoleDefinition module.
#
# Mocks azurerm so plan resolves without credentials. Exercises the variable
# shape, validators, and the role-definition preconditions — no real Azure
# resources are created.
#
# Run with:
#   cd modules/RoleDefinition
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# -----------------------------------------------------------------------
# 1. smoke_control_plane — control-plane role at subscription scope.
# -----------------------------------------------------------------------
run "smoke_control_plane" {
  command = plan

  variables {
    name    = "Restricted vNet Peering"
    scope   = "/subscriptions/00000000-0000-0000-0000-000000000000"
    actions = ["Microsoft.Network/virtualNetworks/peer/action", "Microsoft.Network/virtualNetworks/read"]
  }

  assert {
    condition     = azurerm_role_definition.this.name == "Restricted vNet Peering"
    error_message = "name must pass through."
  }
  assert {
    condition     = length(azurerm_role_definition.this.assignable_scopes) == 1
    error_message = "assignable_scopes must default to [scope]."
  }
}

# -----------------------------------------------------------------------
# 2. smoke_define_and_assign — one-shot definition + SP assignment
#    (delegated to the RoleAssignment module).
# -----------------------------------------------------------------------
run "smoke_define_and_assign" {
  command = plan

  variables {
    name    = "Restricted vNet Peering"
    scope   = "/subscriptions/00000000-0000-0000-0000-000000000000"
    actions = ["Microsoft.Network/virtualNetworks/peer/action"]
    assignments = [{
      scope        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-gwc-hub/providers/Microsoft.Network/virtualNetworks/vnet-con-prod-gwc-hub"
      principal_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }]
  }

  assert {
    condition     = length(module.assignment) == 1
    error_message = "One assignment must be planned per assignments entry."
  }
}

# -----------------------------------------------------------------------
# 3. smoke_management_group — control-plane role created at MG scope.
# -----------------------------------------------------------------------
run "smoke_management_group" {
  command = plan

  variables {
    name    = "MG Alert Rules Manager"
    scope   = "/providers/Microsoft.Management/managementGroups/mg-lzr"
    actions = ["Microsoft.Insights/alertRules/*"]
  }
}

# -----------------------------------------------------------------------
# 4. smoke_data_plane_subscription — data-plane role at subscription
#    scope (allowed; only MG scope is forbidden for data_actions).
# -----------------------------------------------------------------------
run "smoke_data_plane_subscription" {
  command = plan

  variables {
    name         = "KV Secrets Get-Only"
    scope        = "/subscriptions/00000000-0000-0000-0000-000000000000"
    data_actions = ["Microsoft.KeyVault/vaults/secrets/getSecret/action"]
  }
}

# -----------------------------------------------------------------------
# 5. no_permissions_fails — no actions and no data_actions.
# -----------------------------------------------------------------------
run "no_permissions_fails" {
  command = plan

  variables {
    name  = "Empty Role"
    scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [azurerm_role_definition.this]
}

# -----------------------------------------------------------------------
# 6. data_plane_at_mg_fails — data_actions with a management-group
#    assignable scope (Azure forbids this).
# -----------------------------------------------------------------------
run "data_plane_at_mg_fails" {
  command = plan

  variables {
    name         = "Bad Data Role at MG"
    scope        = "/providers/Microsoft.Management/managementGroups/mg-lzr"
    data_actions = ["Microsoft.KeyVault/vaults/secrets/getSecret/action"]
  }

  expect_failures = [azurerm_role_definition.this]
}

# -----------------------------------------------------------------------
# 7. two_management_groups_fails — assignable_scopes with two MGs.
# -----------------------------------------------------------------------
run "two_management_groups_fails" {
  command = plan

  variables {
    name    = "Two MG Role"
    scope   = "/providers/Microsoft.Management/managementGroups/mg-lzr"
    actions = ["Microsoft.Insights/alertRules/read"]
    assignable_scopes = [
      "/providers/Microsoft.Management/managementGroups/mg-lzr",
      "/providers/Microsoft.Management/managementGroups/mg-corp",
    ]
  }

  expect_failures = [azurerm_role_definition.this]
}

# -----------------------------------------------------------------------
# 8. invalid_principal_type_fails — assignment principal_type not in enum.
# -----------------------------------------------------------------------
run "invalid_principal_type_fails" {
  command = plan

  variables {
    name    = "Role"
    scope   = "/subscriptions/00000000-0000-0000-0000-000000000000"
    actions = ["Microsoft.Network/virtualNetworks/read"]
    assignments = [{
      scope          = "/subscriptions/00000000-0000-0000-0000-000000000000"
      principal_id   = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      principal_type = "Computer"
    }]
  }

  expect_failures = [var.assignments]
}

# -----------------------------------------------------------------------
# 9. invalid_principal_id_fails — assignment principal_id is not a GUID.
# -----------------------------------------------------------------------
run "invalid_principal_id_fails" {
  command = plan

  variables {
    name    = "Role"
    scope   = "/subscriptions/00000000-0000-0000-0000-000000000000"
    actions = ["Microsoft.Network/virtualNetworks/read"]
    assignments = [{
      scope        = "/subscriptions/00000000-0000-0000-0000-000000000000"
      principal_id = "not-a-guid"
    }]
  }

  expect_failures = [var.assignments]
}

# -----------------------------------------------------------------------
# 10. invalid_scope_fails — creation scope is not a sub/MG.
# -----------------------------------------------------------------------
run "invalid_scope_fails" {
  command = plan

  variables {
    name    = "Role"
    scope   = "not-a-scope"
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }

  expect_failures = [var.scope]
}
