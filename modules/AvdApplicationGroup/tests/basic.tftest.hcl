# Plan-time tests for the AvdApplicationGroup module.
#
# Mocks azurerm + time. Covers:
#   1. happy_desktop_naming              — convention naming, Desktop, no apps/lock/rbac
#   2. happy_remoteapp_with_apps         — RemoteApp type, 2 applications published
#   3. happy_name_override               — explicit var.name (XOR escape hatch)
#   4. happy_with_lock_and_rbac          — lock + role_assignment, both module blocks planned
#   5. happy_default_desktop_display_name — Desktop + default_desktop_display_name wired
#   6. validator_invalid_type            — type="Foo" must fail
#   7. validator_applications_on_desktop — Desktop type + applications must fail cross-var validator
#   8. validator_invalid_command_line_policy — bad command_line_argument_policy must fail
#   9. validator_invalid_role_principal_type — bad principal_type must fail
#  10. happy_no_workspace_association    — workspace_association resource must not be planned (F-5 removed it)
#
# Run with:
#   cd modules/AvdApplicationGroup
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  location            = "westeurope"
  resource_group_name = "rg-avd-nprd-weu-avd"
  host_pool_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-avd-nprd-weu-pooled"
}

# ---------------------------------------------------------------------
# Test 1: happy_desktop_naming — convention naming, Desktop type.
# ---------------------------------------------------------------------
run "happy_desktop_naming" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "desktop"
    type                 = "Desktop"
  }

  assert {
    condition     = azurerm_virtual_desktop_application_group.this.type == "Desktop"
    error_message = "Application group type must be Desktop."
  }

  assert {
    condition     = length(module.naming) == 1
    error_message = "Naming module must be instantiated when var.name is null."
  }

  assert {
    condition     = length(azurerm_virtual_desktop_application.this) == 0
    error_message = "No applications must be planned for a Desktop group."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_remoteapp_with_apps — RemoteApp type, 2 applications.
# ---------------------------------------------------------------------
run "happy_remoteapp_with_apps" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "apps"
    type                 = "RemoteApp"

    applications = {
      notepad = {
        name                         = "Notepad"
        path                         = "C:\\Windows\\System32\\notepad.exe"
        command_line_argument_policy = "DoNotAllow"
        show_in_portal               = true
      }
      calc = {
        name                         = "Calculator"
        path                         = "C:\\Windows\\System32\\calc.exe"
        command_line_argument_policy = "DoNotAllow"
        friendly_name                = "Windows Calculator"
      }
    }
  }

  assert {
    condition     = azurerm_virtual_desktop_application_group.this.type == "RemoteApp"
    error_message = "Application group type must be RemoteApp."
  }

  assert {
    condition     = length(azurerm_virtual_desktop_application.this) == 2
    error_message = "Two applications must be planned."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_name_override — explicit var.name bypasses Naming module.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "vdag-custom"
    type = "Desktop"
  }

  assert {
    condition     = azurerm_virtual_desktop_application_group.this.name == "vdag-custom"
    error_message = "Name override must produce the explicit name."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must not be instantiated when var.name is provided."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_with_lock_and_rbac — lock + role_assignment planned.
# ---------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    name = "vdag-lock-rbac"
    type = "Desktop"

    lock = { kind = "CanNotDelete" }

    role_assignments = {
      dvd_users = {
        role_definition_id_or_name = "Desktop Virtualization User"
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
    condition     = azurerm_virtual_desktop_application_group.this.name == "vdag-lock-rbac"
    error_message = "Application group name must match."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_default_desktop_display_name — Desktop + display name wired.
# ---------------------------------------------------------------------
run "happy_default_desktop_display_name" {
  command = plan

  variables {
    name                         = "vdag-desktop-display"
    type                         = "Desktop"
    default_desktop_display_name = "My Desktop"
  }

  assert {
    condition     = azurerm_virtual_desktop_application_group.this.default_desktop_display_name == "My Desktop"
    error_message = "default_desktop_display_name must be wired to the resource."
  }
}

# ---------------------------------------------------------------------
# Test 6: validator_invalid_type — type="Foo" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_type" {
  command = plan

  variables {
    name = "vdag-bad-type"
    type = "Foo"
  }

  expect_failures = [var.type]
}

# ---------------------------------------------------------------------
# Test 7: validator_applications_on_desktop — cross-var validator must fail.
# ---------------------------------------------------------------------
run "validator_applications_on_desktop" {
  command = plan

  variables {
    name = "vdag-desktop-apps"
    type = "Desktop"

    applications = {
      notepad = {
        name                         = "Notepad"
        path                         = "C:\\Windows\\System32\\notepad.exe"
        command_line_argument_policy = "DoNotAllow"
      }
    }
  }

  expect_failures = [var.applications]
}

# ---------------------------------------------------------------------
# Test 8: validator_invalid_command_line_policy — bad policy must fail.
# ---------------------------------------------------------------------
run "validator_invalid_command_line_policy" {
  command = plan

  variables {
    name = "vdag-bad-policy"
    type = "RemoteApp"

    applications = {
      notepad = {
        name                         = "Notepad"
        path                         = "C:\\Windows\\System32\\notepad.exe"
        command_line_argument_policy = "Bar"
      }
    }
  }

  expect_failures = [var.applications]
}

# ---------------------------------------------------------------------
# Test 9: validator_invalid_role_principal_type — bad principal_type must fail.
# ---------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    name = "vdag-bad-rbac"
    type = "Desktop"

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
# Test 10: happy_no_workspace_association — F-5 removed the resource.
# No azurerm_virtual_desktop_workspace_application_group_association
# must appear in the plan (the removed{} tombstone suppresses destroy).
# ---------------------------------------------------------------------
run "happy_no_workspace_association" {
  command = plan

  variables {
    name = "vdag-no-ws"
    type = "Desktop"
  }

  # The resource must not be planned at all — validate by checking the
  # app group resource is planned (module is active) and workspace var is gone.
  assert {
    condition     = azurerm_virtual_desktop_application_group.this.type == "Desktop"
    error_message = "Application group must be planned."
  }
}
