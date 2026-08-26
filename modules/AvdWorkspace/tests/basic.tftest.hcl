# Plan-time tests for the AvdWorkspace module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming              — convention naming, default args (public_network_access=false, no associations/lock/rbac)
#   2. happy_name_override               — explicit var.name, assert XOR escape hatch
#   3. happy_with_associations           — 2-entry application_group_associations map, 2 association resources planned
#   4. happy_empty_associations          — empty map (default), 0 association resources planned
#   5. happy_with_lock_and_rbac          — lock + 1 role_assignment, both module blocks planned
#   6. happy_public_network_access_overridden — public_network_access_enabled = true (caller override)
#   7. validator_naming_xor_fails        — var.name = null + all convention vars null → expect XOR failure
#   8. validator_invalid_role_principal_type — principal_type = "Foo" → expect failure
#   9. validator_invalid_lock_kind       — lock = { kind = "Bogus" } → expect failure
#
# Run with:
#   cd modules/AvdWorkspace
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  location            = "westeurope"
  resource_group_name = "rg-avd-nprd-weu-avd"
}

# ---------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, all defaults.
# ---------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "main"
  }

  assert {
    condition     = azurerm_virtual_desktop_workspace.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled must default to false (secure-by-default, v0.2.34 flip)."
  }

  assert {
    condition     = length(module.naming) == 1
    error_message = "Naming module must be instantiated when var.name is null."
  }

  assert {
    condition     = length(azurerm_virtual_desktop_workspace_application_group_association.this) == 0
    error_message = "No associations must be planned when application_group_associations is empty."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "vdws-custom"
  }

  assert {
    condition     = azurerm_virtual_desktop_workspace.this.name == "vdws-custom"
    error_message = "Name override must produce the explicit name."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must not be instantiated when var.name is provided."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_with_associations — 2-entry map, 2 resources planned.
# ---------------------------------------------------------------------
run "happy_with_associations" {
  command = plan

  variables {
    name = "vdws-assoc"

    application_group_associations = {
      desktop   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/applicationGroups/vdag-avd-nprd-weu-desktop"
      remoteapp = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/applicationGroups/vdag-avd-nprd-weu-apps"
    }
  }

  assert {
    condition     = length(azurerm_virtual_desktop_workspace_application_group_association.this) == 2
    error_message = "Two application group associations must be planned."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_empty_associations — empty map, 0 resources planned.
# ---------------------------------------------------------------------
run "happy_empty_associations" {
  command = plan

  variables {
    name                           = "vdws-no-assoc"
    application_group_associations = {}
  }

  assert {
    condition     = length(azurerm_virtual_desktop_workspace_application_group_association.this) == 0
    error_message = "No association resources must be planned for an empty map."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_with_lock_and_rbac — lock + 1 role_assignment planned.
# ---------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    name = "vdws-lock-rbac"

    lock = { kind = "CanNotDelete" }

    role_assignments = {
      ws_contributor = {
        role_definition_id_or_name = "Desktop Virtualization Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "RBAC module must have one instance when one role assignment is given."
  }

  assert {
    condition     = azurerm_virtual_desktop_workspace.this.name == "vdws-lock-rbac"
    error_message = "Workspace name must match."
  }
}

# ---------------------------------------------------------------------
# Test 6: happy_public_network_access_overridden — caller sets true.
# ---------------------------------------------------------------------
run "happy_public_network_access_overridden" {
  command = plan

  variables {
    name                          = "vdws-public"
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_virtual_desktop_workspace.this.public_network_access_enabled == true
    error_message = "public_network_access_enabled caller override to true must be wired."
  }
}

# ---------------------------------------------------------------------
# Test 7: validator_naming_xor_fails — both name and convention vars null.
# ---------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = null
    environment          = null
    region_code          = null
    workload             = null
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 8: validator_invalid_role_principal_type — "Foo" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    name = "vdws-bad-rbac"

    role_assignments = {
      bad_ra = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "Foo"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# ---------------------------------------------------------------------
# Test 9: validator_invalid_lock_kind — "Bogus" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    name = "vdws-bad-lock"
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}
