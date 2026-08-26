# Plan-time tests for the ManagedHsm module.
#
# Mocks azurerm + time.
#
# Covers:
#   1. happy_default   — derived name + forced-secure posture
#   2. name_override   — explicit var.name wins
#   3. workload_suffix — optional workload appended to the name
#   4. with_lock       — optional lock scoped to the HSM
#   5. validator_admin_object_ids_empty  — empty admin list → fail
#   6. validator_soft_delete_below_min   — retention 5 → fail
#   7. validator_bad_sku                 — invalid sku → fail
#   8. validator_bad_network_default_action — invalid default_action → fail
#   9. validator_name_override_too_long  — 25-char name → fail
#
# Run with:
#   cd modules/ManagedHsm
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs.
variables {
  subscription_acronym = "idt"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-idt-prod-gwc-hsm"
  tenant_id            = "00000000-0000-0000-0000-000000000000"
  admin_object_ids     = ["11111111-1111-1111-1111-111111111111"]
}

# -----------------------------------------------------------------------
# Test 1: happy_default — derived name + hardened defaults.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.name == "mhsm-idt-prod-gwc"
    error_message = "Name must derive as mhsm-{acronym}-{env}-{region} (no workload)."
  }

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.purge_protection_enabled == true
    error_message = "Purge protection must be forced ON."
  }

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.public_network_access_enabled == false
    error_message = "Public network access must default to OFF."
  }

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.soft_delete_retention_days == 90
    error_message = "soft_delete_retention_days must default to 90."
  }

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.network_acls[0].default_action == "Deny" && azurerm_key_vault_managed_hardware_security_module.this.network_acls[0].bypass == "AzureServices"
    error_message = "network_acls must default to deny-by-default with AzureServices bypass."
  }
}

# -----------------------------------------------------------------------
# Test 2: name_override — explicit var.name wins.
# -----------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name = "mhsm-legacy-01"
  }

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.name == "mhsm-legacy-01"
    error_message = "var.name must override the derived name."
  }
}

# -----------------------------------------------------------------------
# Test 3: workload_suffix — optional workload appended.
# -----------------------------------------------------------------------
run "workload_suffix" {
  command = plan

  variables {
    workload = "keys"
  }

  assert {
    condition     = azurerm_key_vault_managed_hardware_security_module.this.name == "mhsm-idt-prod-gwc-keys"
    error_message = "workload must append as the last name segment when set."
  }
}

# -----------------------------------------------------------------------
# Test 4: with_lock — optional lock scoped to the HSM.
# -----------------------------------------------------------------------
run "with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "One lock must be planned when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 4b: local_rbac — data-plane role assignments composed (built-in
#          role name + explicit role id). NOTE: at real apply these need
#          the HSM activated; under mock_provider they plan fine.
# -----------------------------------------------------------------------
run "local_rbac" {
  command = plan

  variables {
    role_assignments = {
      crypto_user = {
        principal_id         = "22222222-2222-2222-2222-222222222222"
        role_definition_name = "Managed HSM Crypto User"
        scope                = "/keys"
      }
      custom = {
        principal_id       = "33333333-3333-3333-3333-333333333333"
        role_definition_id = "/Microsoft.KeyVault/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000000"
        scope              = "/"
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_managed_hardware_security_module_role_assignment.this) == 2
    error_message = "Two local-RBAC role assignments must be planned."
  }

  assert {
    condition     = length(data.azurerm_key_vault_managed_hardware_security_module_role_definition.this) == 1
    error_message = "Only the built-in-name entry must resolve a role definition (the explicit-id entry must not)."
  }
}

# -----------------------------------------------------------------------
# Test 4c: validator_rbac_both_role_refs — name AND id set → fail.
# -----------------------------------------------------------------------
run "validator_rbac_both_role_refs" {
  command = plan

  variables {
    role_assignments = {
      bad = {
        principal_id         = "22222222-2222-2222-2222-222222222222"
        role_definition_name = "Managed HSM Crypto User"
        role_definition_id   = "/Microsoft.KeyVault/.../roleDefinitions/x"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# -----------------------------------------------------------------------
# Test 5: validator_admin_object_ids_empty — empty list → fail.
# -----------------------------------------------------------------------
run "validator_admin_object_ids_empty" {
  command = plan

  variables {
    admin_object_ids = []
  }

  expect_failures = [var.admin_object_ids]
}

# -----------------------------------------------------------------------
# Test 6: validator_soft_delete_below_min — retention 5 → fail.
# -----------------------------------------------------------------------
run "validator_soft_delete_below_min" {
  command = plan

  variables {
    soft_delete_retention_days = 5
  }

  expect_failures = [var.soft_delete_retention_days]
}

# -----------------------------------------------------------------------
# Test 7: validator_bad_sku — invalid sku → fail.
# -----------------------------------------------------------------------
run "validator_bad_sku" {
  command = plan

  variables {
    sku_name = "Standard_B2"
  }

  expect_failures = [var.sku_name]
}

# -----------------------------------------------------------------------
# Test 8: validator_bad_network_default_action — invalid value → fail.
# -----------------------------------------------------------------------
run "validator_bad_network_default_action" {
  command = plan

  variables {
    network_acls = { default_action = "Reject" }
  }

  expect_failures = [var.network_acls]
}

# -----------------------------------------------------------------------
# Test 9: validator_name_override_too_long — 25-char name → fail.
# -----------------------------------------------------------------------
run "validator_name_override_too_long" {
  command = plan

  variables {
    name = "mhsm-way-too-long-name-123"
  }

  expect_failures = [var.name]
}
