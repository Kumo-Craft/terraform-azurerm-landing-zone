# Plan-time tests for the KeyVault-Secrets module.
#
# Mocks azurerm + time + random. Covers:
#   - Caller-supplied value (happy path)
#   - Auto-generated secret (generate = true)
#   - Multi-secret map (3 secrets)
#   - Validator: secret name starting with digit must fail
#   - Validator: invalid key_vault_id must fail
#   - Validator: value AND generate both set must fail (mutual-exclusion)
#   - Validator: neither value nor generate set must fail
#   - Validator: invalid expiration_date format must fail (F1.2)
#
# Run with:
#   cd modules/KeyVault-Secrets
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}
mock_provider "random" {}

# ---------------------------------------------------------------------
# Test 1: Caller-supplied value — happy path.
# ---------------------------------------------------------------------
run "caller_value_happy" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "admin-password" = {
        name  = "admin-password"
        value = "test-password"
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 1
    error_message = "Caller-value happy path must produce exactly one azurerm_key_vault_secret resource."
  }
}

# ---------------------------------------------------------------------
# Test 2: Auto-generated secret (generate = true) — happy path.
# ---------------------------------------------------------------------
run "generate_happy" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "api-key" = {
        name = "api-key"
        generate = {
          length = 16
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 1
    error_message = "Generate happy path must produce exactly one azurerm_key_vault_secret resource."
  }
}

# ---------------------------------------------------------------------
# Test 3: Multi-secret map — 3 secrets (value + generate + typed).
# ---------------------------------------------------------------------
run "multi_secret_happy" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "admin-password" = {
        name  = "admin-password"
        value = "test-password"
      }
      "generated-secret" = {
        name = "generated-secret"
        generate = {
          length = 32
        }
      }
      "api-key" = {
        name            = "api-key"
        value           = "some-api-key"
        content_type    = "application/json"
        expiration_date = "2027-12-31T23:59:00Z"
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 3
    error_message = "Multi-secret map must produce exactly three azurerm_key_vault_secret resources."
  }
}

# ---------------------------------------------------------------------
# Test 4: Secret name starting with digit — must fail (name validator).
# ---------------------------------------------------------------------
run "invalid_name_fails" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "1bad-name" = {
        name  = "1bad-name"
        value = "test-value"
      }
    }
  }

  expect_failures = [var.secrets]
}

# ---------------------------------------------------------------------
# Test 5: Invalid key_vault_id — must fail (key_vault_id regex validator).
# ---------------------------------------------------------------------
run "invalid_key_vault_id_fails" {
  command = plan

  variables {
    key_vault_id = "not-an-ARM-id"
    secrets = {
      "my-secret" = {
        name  = "my-secret"
        value = "test-value"
      }
    }
  }

  expect_failures = [var.key_vault_id]
}

# ---------------------------------------------------------------------
# Test 6: value AND generate both set — must fail (mutual-exclusion validator).
# ---------------------------------------------------------------------
run "value_and_generate_both_set_fails" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "bad-secret" = {
        name  = "bad-secret"
        value = "x"
        generate = {
          length = 16
        }
      }
    }
  }

  expect_failures = [var.secrets]
}

# ---------------------------------------------------------------------
# Test 7: Neither value nor generate set — must fail (mutual-exclusion validator).
# ---------------------------------------------------------------------
run "neither_value_nor_generate_fails" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "empty-secret" = {
        name = "empty-secret"
      }
    }
  }

  expect_failures = [var.secrets]
}

# ---------------------------------------------------------------------
# Test 8: Invalid expiration_date format — must fail (F1.2 RFC3339 validator).
# ---------------------------------------------------------------------
run "invalid_expiration_date_fails" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    secrets = {
      "bad-expiry" = {
        name            = "bad-expiry"
        value           = "test-value"
        expiration_date = "2027/01/01"
      }
    }
  }

  expect_failures = [var.secrets]
}
