# Plan-time tests for the SqlManagedInstance module.
#
# Mocks azurerm. Covers:
#   1. happy_default_naming        — convention naming + secure defaults
#   2. happy_name_override         — explicit var.name (XOR escape hatch)
#   3. happy_entra_admin           — azure_active_directory_administrator block wired
#   4. happy_with_identity         — SystemAssigned identity block wired
#   5. happy_with_lock_and_rbac    — var.lock + 1 role_assignment
#   6. validator_naming_xor_fails  — name=null + naming vars=null → failure
#   7. validator_invalid_subnet_id — non-subnet ID → failure
#   8. validator_invalid_sku       — sku not GP_/BC_ → failure
#   9. validator_vcores_too_low    — vcores 3 → failure
#  10. validator_no_admin          — no SQL creds + no entra admin → precondition failure
#  11. validator_invalid_lock_kind — lock.kind = "Bogus" → failure
#  12. validator_invalid_role_principal — principal_type = "Foo" → failure
#
# Run with:
#   cd modules/SqlManagedInstance
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs. A SQL admin is supplied so the admin precondition
# is satisfied for the happy runs.
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-sqlmi"
  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-frc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-frc/subnets/snet-sqlmi"

  administrator_login          = "sqladminuser"
  administrator_login_password = "P@ssw0rd-Example-1234!"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming + secure defaults.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_mssql_managed_instance.this.name == "sqlmi-mgm-prod-frc-01"
    error_message = "MI name must follow the sqlmi-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azurerm_mssql_managed_instance.this.public_data_endpoint_enabled == false
    error_message = "public_data_endpoint_enabled must default to false (private-only)."
  }

  assert {
    condition     = azurerm_mssql_managed_instance.this.minimum_tls_version == "1.2"
    error_message = "minimum_tls_version must default to 1.2."
  }

  assert {
    condition     = azurerm_mssql_managed_instance.this.sku_name == "GP_Gen5" && azurerm_mssql_managed_instance.this.license_type == "LicenseIncluded"
    error_message = "Defaults must be GP_Gen5 / LicenseIncluded."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "sqlmi-legacy-custom"
  }

  assert {
    condition     = azurerm_mssql_managed_instance.this.name == "sqlmi-legacy-custom"
    error_message = "MI name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_entra_admin — Entra admin block wired.
# -----------------------------------------------------------------------
run "happy_entra_admin" {
  command = plan

  variables {
    entra_administrator = {
      login_username                      = "sql-admins"
      object_id                           = "00000000-0000-0000-0000-000000000009"
      principal_type                      = "Group"
      azuread_authentication_only_enabled = true
    }
  }

  assert {
    condition     = length(azurerm_mssql_managed_instance.this.azure_active_directory_administrator) == 1
    error_message = "azure_active_directory_administrator block must be emitted when entra_administrator is set."
  }

  assert {
    condition     = azurerm_mssql_managed_instance.this.azure_active_directory_administrator[0].principal_type == "Group"
    error_message = "entra_administrator.principal_type must wire through."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_identity — SystemAssigned identity block wired.
# -----------------------------------------------------------------------
run "happy_with_identity" {
  command = plan

  variables {
    identity = { type = "SystemAssigned" }
  }

  assert {
    condition     = azurerm_mssql_managed_instance.this.identity[0].type == "SystemAssigned"
    error_message = "identity block must wire type through."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_lock_and_rbac — lock + 1 role assignment.
# -----------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      "reader" = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One rbac module instance must be planned for 1 role assignment."
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_naming_xor_fails — name=null + naming vars=null → failure.
# -----------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_subnet_id — non-subnet ID → failure.
# -----------------------------------------------------------------------
run "validator_invalid_subnet_id" {
  command = plan

  variables {
    subnet_id = "/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/virtualNetworks/vnet-x"
  }

  expect_failures = [var.subnet_id]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_sku — sku not GP_/BC_ → failure.
# -----------------------------------------------------------------------
run "validator_invalid_sku" {
  command = plan

  variables {
    sku_name = "Bogus_Gen5"
  }

  expect_failures = [var.sku_name]
}

# -----------------------------------------------------------------------
# Test 9: validator_vcores_too_low — vcores 3 → failure.
# -----------------------------------------------------------------------
run "validator_vcores_too_low" {
  command = plan

  variables {
    vcores = 3
  }

  expect_failures = [var.vcores]
}

# -----------------------------------------------------------------------
# Test 10: validator_no_admin — no SQL creds + no entra admin → precondition.
# -----------------------------------------------------------------------
run "validator_no_admin" {
  command = plan

  variables {
    administrator_login          = null
    administrator_login_password = null
    entra_administrator          = null
  }

  expect_failures = [azurerm_mssql_managed_instance.this]
}

# -----------------------------------------------------------------------
# Test 11: validator_invalid_lock_kind — "Bogus" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 12: validator_invalid_role_principal_type — "Foo" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    role_assignments = {
      "bad" = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "Foo"
      }
    }
  }

  expect_failures = [var.role_assignments]
}
