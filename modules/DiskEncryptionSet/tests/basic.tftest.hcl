###############################################################
# MODULE: DiskEncryptionSet - Tests
#
# plan-only, no credentials. The provider block is skipped so the
# azurerm provider never authenticates.
###############################################################

mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  resource_group_name = "rg-test"
  location            = "germanywestcentral"
  key_vault_key_id    = "https://kv-test.vault.azure.net/keys/des-key"
  key_vault_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
}

# ---------------------------------------------------------------------
# Test 1: generated name follows des-{acr}-{env}-{region}-{workload}.
# ---------------------------------------------------------------------
run "generated_name_happy" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "01"
  }

  assert {
    condition     = azurerm_disk_encryption_set.this.name == "des-avd-prod-gwc-01"
    error_message = "Generated name must be des-{acr}-{env}-{region}-{workload}."
  }

  # The default that matters for the guardrail: CMK on the disk data.
  assert {
    condition     = azurerm_disk_encryption_set.this.encryption_type == "EncryptionAtRestWithCustomerKey"
    error_message = "Default encryption_type must be EncryptionAtRestWithCustomerKey (what deny-osanddatadisk-cmk requires)."
  }

  assert {
    condition     = azurerm_disk_encryption_set.this.auto_key_rotation_enabled
    error_message = "Key rotation must default to on — a CMK that never rotates buys the checkbox and none of the security."
  }

  assert {
    condition     = azurerm_disk_encryption_set.this.identity[0].type == "SystemAssigned"
    error_message = "Default identity must be SystemAssigned."
  }
}

# ---------------------------------------------------------------------
# Test 2: explicit name wins and keeps the naming module out of the graph.
# ---------------------------------------------------------------------
run "explicit_name_overrides" {
  command = plan

  variables {
    name = "des-legacy-override"
  }

  assert {
    condition     = azurerm_disk_encryption_set.this.name == "des-legacy-override"
    error_message = "Explicit var.name must win over the generated name."
  }
}

# ---------------------------------------------------------------------
# Test 3: the key grant is wired to the DES identity with the
# least-privilege role — NOT Crypto Officer, which could delete the key.
# ---------------------------------------------------------------------
run "key_access_uses_least_privilege_role" {
  command = plan

  variables {
    name = "des-rbac-test"
  }

  assert {
    condition     = module.key_access["this"].role_definition_name == "Key Vault Crypto Service Encryption User"
    error_message = "The DES identity must get 'Key Vault Crypto Service Encryption User' — never an officer role that can delete the key it depends on."
  }

  assert {
    condition     = module.key_access["this"].scope == var.key_vault_id
    error_message = "The key grant must be scoped to the Key Vault."
  }
}

# ---------------------------------------------------------------------
# Test 4: key_vault_id = null opts out of the grant entirely.
# ---------------------------------------------------------------------
run "no_key_vault_id_skips_grant" {
  command = plan

  variables {
    name         = "des-nograntt"
    key_vault_id = null
  }

  assert {
    condition     = length(module.key_access) == 0
    error_message = "key_vault_id = null must emit no role assignment."
  }
}

# ---------------------------------------------------------------------
# Test 5: the SILENT failure mode — rotation on + a versioned key id.
# Nothing errors at runtime; the key simply never rotates. Must be
# caught at plan time.
# ---------------------------------------------------------------------
run "rotation_with_versioned_key_fails" {
  command = plan

  variables {
    name                      = "des-rotbad01"
    key_vault_key_id          = "https://kv-test.vault.azure.net/keys/des-key/9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
    auto_key_rotation_enabled = true
  }

  expect_failures = [var.auto_key_rotation_enabled]
}

run "no_rotation_with_versionless_key_fails" {
  command = plan

  variables {
    name                      = "des-rotbad02"
    key_vault_key_id          = "https://kv-test.vault.azure.net/keys/des-key"
    auto_key_rotation_enabled = false
  }

  expect_failures = [var.auto_key_rotation_enabled]
}

run "pinned_version_without_rotation_happy" {
  command = plan

  variables {
    name                      = "des-pinned001"
    key_vault_key_id          = "https://kv-test.vault.azure.net/keys/des-key/9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
    auto_key_rotation_enabled = false
  }

  assert {
    condition     = azurerm_disk_encryption_set.this.auto_key_rotation_enabled == false
    error_message = "A pinned key version with rotation off is a legitimate configuration."
  }
}

# ---------------------------------------------------------------------
# Test 6: identity_type and its ids must agree.
# ---------------------------------------------------------------------
run "user_assigned_without_ids_fails" {
  command = plan

  variables {
    name          = "des-uaibad001"
    identity_type = "UserAssigned"
  }

  expect_failures = [var.user_assigned_identity_ids]
}

run "system_assigned_with_ids_fails" {
  command = plan

  variables {
    name                       = "des-uaibad002"
    identity_type              = "SystemAssigned"
    user_assigned_identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-test"]
  }

  expect_failures = [var.user_assigned_identity_ids]
}

# ---------------------------------------------------------------------
# Test 7: ConfidentialVmEncryptedWithCustomerKey is accepted by the
# module but is a Confidential-VM-only mode. Documented, not blocked —
# the module can't tell what will consume the DES.
# ---------------------------------------------------------------------
run "invalid_encryption_type_fails" {
  command = plan

  variables {
    name            = "des-enctype001"
    encryption_type = "EncryptionAtRestWithPlatformKey"
  }

  expect_failures = [var.encryption_type]
}

# ---------------------------------------------------------------------
# Test 8: naming inputs must be complete when var.name is null.
# ---------------------------------------------------------------------
run "incomplete_naming_inputs_fail" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "prod"
    # region_code and workload deliberately missing
  }

  expect_failures = [var.name]
}
