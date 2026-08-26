# Plan-time tests for KeyVault module.
#
# These tests run via `terraform test` and only exercise validation logic
# + plan resolution — no real Azure resources are created. They serve as
# a smoke test for the variable shape and validators.
#
# Run locally with:
#   cd KeyVault
#   terraform init -backend=false
#   terraform test

# ---------------------------------------------------------------------
# Provider mocks — required so plan can resolve azurerm without creds.
# ---------------------------------------------------------------------
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

# ---------------------------------------------------------------------
# Test 1: Smoke test — minimal valid input produces a clean plan.
# ---------------------------------------------------------------------
run "smoke" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "test"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-nprd-gwc-test"
  }

  assert {
    condition     = output.name == "kv-mgm-nprd-gwc-test"
    error_message = "Computed Key Vault name must follow the {prefix}-{acr}-{env}-{region}-{workload} convention."
  }
}

# ---------------------------------------------------------------------
# Test 2: Validator — KV name max 24 chars precondition.
# ---------------------------------------------------------------------
run "name_too_long_fails_validation" {
  command = plan

  variables {
    name                 = "this-name-is-definitely-way-too-long-to-be-a-valid-key-vault-name"
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "test"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-nprd-gwc-test"
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 3: Role assignments — Shape A canonical (8-field).
# ---------------------------------------------------------------------
run "role_assignments_full_shape" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "test"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-nprd-gwc-test"

    role_assignments = {
      reader_group = {
        role_definition_id_or_name = "Key Vault Reader"
        principal_id               = "22222222-2222-2222-2222-222222222222"
        principal_type             = "Group"
        description                = "smoke-test entry"
      }
      cross_tenant_mi = {
        role_definition_id_or_name             = "Key Vault Secrets User"
        principal_id                           = "33333333-3333-3333-3333-333333333333"
        principal_type                         = "ServicePrincipal"
        skip_service_principal_aad_check       = true
        delegated_managed_identity_resource_id = "/subscriptions/.../userAssignedIdentities/cross-tenant-mi"
      }
    }
  }
}

# ---------------------------------------------------------------------
# Test 4: Network ACLs — bypass enum validator.
# ---------------------------------------------------------------------
run "network_acls_invalid_bypass_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "test"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-nprd-gwc-test"

    network_acls = {
      default_action = "Deny"
      bypass         = "InvalidValue" # must be AzureServices or None
    }
  }

  expect_failures = [var.network_acls]
}

# ---------------------------------------------------------------------
# Test 5: Legacy name escape-hatch — explicit `name` bypasses Naming module.
# ---------------------------------------------------------------------
run "legacy_name_override" {
  command = plan

  variables {
    name                = "kv-existing-vault-01"
    location            = "germanywestcentral"
    resource_group_name = "rg-mgm-prod-gwc-existing"
  }

  assert {
    condition     = output.name == "kv-existing-vault-01"
    error_message = "Legacy name override must pass through unchanged."
  }
}
