# Plan-time tests for the AvdSessionHost module.
#
# Mocks azurerm + time + random. Covers:
#   1. happy_default_image         — convention naming, default image, patch_mode=AutomaticByPlatform
#   2. happy_name_override         — explicit var.name (XOR escape hatch), no convention naming
#   3. happy_windows_server_license — license_type = "Windows_Server"
#   4. happy_patch_mode_manual     — patch_mode = "Manual", patch_assessment_mode = ImageDefault
#   5. happy_with_lock_and_rbac    — var.lock + role_assignment, both module blocks planned
#   6. happy_encryption_at_host_disabled — encryption_at_host_enabled = false (override secure default)
#   7. validator_invalid_license_type   — license_type = "Foo" must fail
#   8. validator_invalid_patch_mode     — patch_mode = "Bar" must fail
#   9. validator_invalid_role_principal_type — role_assignments with bad principal_type must fail
#  10. validator_naming_xor_fails       — var.name=null + var.workload=null must fail XOR validator
#  11. happy_no_image_plan              — default image_plan=null renders no plan block
#  12. happy_image_plan_m365            — image_plan set renders a plan block (M365 marketplace image)
#  13. happy_source_image_id           — source_image_id set: source_image_reference + plan suppressed
#  14. validator_invalid_source_image_id — malformed source_image_id must fail
#
# Run with:
#   cd modules/AvdSessionHost
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {
  mock_data "azurerm_key_vault_secret" {
    defaults = {
      # Must satisfy azurerm admin_password complexity: upper + lower + digit + special
      value = "MockP@ssw0rd123!"
    }
  }
}
mock_provider "time" {}
mock_provider "random" {}

# Shared required inputs reused across happy-path runs.
variables {
  location                    = "westeurope"
  resource_group_name         = "rg-avd-nprd-weu-sh"
  subnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.Network/virtualNetworks/vnet-avd/subnets/snet-avd"
  admin_password_kv_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd/providers/Microsoft.KeyVault/vaults/kv-avd-nprd-weu"
  hostpool_name               = "vdpool-avd-nprd-weu-pooled"
  hostpool_registration_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.dGVzdA.dGVzdA"
  fslogix_vhd_location        = "\\\\stavdfslogix.file.core.windows.net\\profiles"
}

# ---------------------------------------------------------------------
# Test 1: happy_default_image — convention naming, AutomaticByPlatform.
# ---------------------------------------------------------------------
run "happy_default_image" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"

    vm_count                   = 1
    patch_mode                 = "AutomaticByPlatform"
    encryption_at_host_enabled = true
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].patch_mode == "AutomaticByPlatform"
    error_message = "patch_mode must be AutomaticByPlatform."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].patch_assessment_mode == "AutomaticByPlatform"
    error_message = "patch_assessment_mode must be AutomaticByPlatform when patch_mode = AutomaticByPlatform."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].provision_vm_agent == true
    error_message = "provision_vm_agent must be true."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].encryption_at_host_enabled == true
    error_message = "encryption_at_host_enabled must default to true."
  }

  assert {
    condition     = azurerm_network_interface.this["01"].ip_forwarding_enabled == false
    error_message = "ip_forwarding_enabled must be false."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses Naming module.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "vm-custom-sh"

    vm_count = 1
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].name == "vm-custom-sh-01"
    error_message = "VM name must use var.name as base with -01 suffix."
  }

  # When var.name is set, module.naming must have zero instances (XOR).
  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must not be instantiated when var.name is provided."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_windows_server_license — license_type = "Windows_Server".
# ---------------------------------------------------------------------
run "happy_windows_server_license" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"

    license_type = "Windows_Server"
    vm_count     = 1
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].license_type == "Windows_Server"
    error_message = "license_type must be Windows_Server."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_patch_mode_manual — patch_assessment_mode = ImageDefault.
# ---------------------------------------------------------------------
run "happy_patch_mode_manual" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"

    patch_mode = "Manual"
    vm_count   = 1
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].patch_assessment_mode == "ImageDefault"
    error_message = "patch_assessment_mode must be ImageDefault when patch_mode != AutomaticByPlatform."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].bypass_platform_safety_checks_on_user_schedule_enabled == null
    error_message = "bypass_platform_safety_checks_on_user_schedule_enabled must be null when patch_mode = Manual."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_with_lock_and_rbac — lock + role_assignment planned.
# ---------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"

    vm_count = 1

    lock = { kind = "CanNotDelete" }

    role_assignments = {
      vm_user_login = {
        role_definition_id_or_name = "Virtual Machine User Login"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "Group"
      }
    }
  }

  # lock module has one instance per VM
  assert {
    condition     = length(module.lock) == 1
    error_message = "Lock module must have one instance per session host VM."
  }

  # rbac module has one instance per role×VM combination
  assert {
    condition     = length(module.rbac) == 1
    error_message = "RBAC module must have one instance per role×VM combination."
  }
}

# ---------------------------------------------------------------------
# Test 6: happy_encryption_at_host_disabled — override secure default.
# ---------------------------------------------------------------------
run "happy_encryption_at_host_disabled" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"

    vm_count                   = 1
    encryption_at_host_enabled = false
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].encryption_at_host_enabled == false
    error_message = "encryption_at_host_enabled must be false when explicitly set."
  }
}

# ---------------------------------------------------------------------
# Test 7: validator_invalid_license_type — "Foo" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_license_type" {
  command = plan

  variables {
    name         = "vm-test"
    license_type = "Foo"
    vm_count     = 1
  }

  expect_failures = [var.license_type]
}

# ---------------------------------------------------------------------
# Test 8: validator_invalid_patch_mode — "Bar" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_patch_mode" {
  command = plan

  variables {
    name       = "vm-test"
    patch_mode = "Bar"
    vm_count   = 1
  }

  expect_failures = [var.patch_mode]
}

# ---------------------------------------------------------------------
# Test 9: validator_invalid_role_principal_type — bad principal_type must fail.
# ---------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    name     = "vm-test"
    vm_count = 1

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
# Test 10: validator_naming_xor_fails — var.name=null + var.workload=null.
# ---------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    # name is null (default) and workload is set but subscription_acronym is not,
    # triggering the XOR cross-var validator on var.name.
    subscription_acronym = null
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"
    vm_count             = 1
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 11: happy_no_image_plan — default image_plan=null => no plan block.
# ---------------------------------------------------------------------
run "happy_no_image_plan" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"
    vm_count             = 1
  }

  assert {
    condition     = length(azurerm_windows_virtual_machine.this["01"].plan) == 0
    error_message = "No plan block must be rendered when image_plan is null (first-party image)."
  }
}

# ---------------------------------------------------------------------
# Test 12: happy_image_plan_m365 — image_plan set => plan block rendered.
# ---------------------------------------------------------------------
run "happy_image_plan_m365" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"
    vm_count             = 1

    image = {
      publisher = "microsoftwindowsdesktop"
      offer     = "office-365"
      sku       = "win11-25h2-avd-m365"
      version   = "latest"
    }
    image_plan = {
      publisher = "microsoftwindowsdesktop"
      product   = "office-365"
      name      = "win11-25h2-avd-m365"
    }
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].plan[0].name == "win11-25h2-avd-m365"
    error_message = "plan.name must match the image_plan input."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].plan[0].product == "office-365"
    error_message = "plan.product must match the image_plan input."
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].plan[0].publisher == "microsoftwindowsdesktop"
    error_message = "plan.publisher must match the image_plan input."
  }
}

# ---------------------------------------------------------------------
# Test 13: happy_source_image_id — custom gallery image takes precedence:
# source_image_id is set, and both source_image_reference + plan blocks
# are suppressed even though image_plan is supplied.
# ---------------------------------------------------------------------
run "happy_source_image_id" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "sh"
    vm_count             = 1

    source_image_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-shared/providers/Microsoft.Compute/galleries/gal_avd/images/win11-avd-golden/versions/1.0.3"

    # Supplied but must be ignored while source_image_id is set.
    image_plan = {
      publisher = "microsoftwindowsdesktop"
      product   = "office-365"
      name      = "win11-25h2-avd-m365"
    }
  }

  assert {
    condition     = azurerm_windows_virtual_machine.this["01"].source_image_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-shared/providers/Microsoft.Compute/galleries/gal_avd/images/win11-avd-golden/versions/1.0.3"
    error_message = "source_image_id must be passed through to the VM."
  }

  assert {
    condition     = length(azurerm_windows_virtual_machine.this["01"].source_image_reference) == 0
    error_message = "source_image_reference must be suppressed when source_image_id is set."
  }

  assert {
    condition     = length(azurerm_windows_virtual_machine.this["01"].plan) == 0
    error_message = "plan block must be suppressed when source_image_id is set, even if image_plan is supplied."
  }
}

# ---------------------------------------------------------------------
# Test 14: validator_invalid_source_image_id — malformed ID must fail.
# ---------------------------------------------------------------------
run "validator_invalid_source_image_id" {
  command = plan

  variables {
    name            = "vm-test"
    vm_count        = 1
    source_image_id = "not-a-valid-resource-id"
  }

  expect_failures = [var.source_image_id]
}
