# Plan-time tests for the KeyVault-Key module.
#
# Mocks azurerm + time. Covers:
#   - RSA key happy path
#   - EC key happy path
#   - Multi-key happy path (RSA + EC + RSA-HSM)
#   - Validator: rotation_policy automatic with BOTH fields set must fail (XOR)
#   - Validator: rotation_policy automatic with NEITHER field set must fail (XOR)
#   - Validator: invalid key_opts value must fail
#   - Validator: invalid key_vault_id must fail
#   - Validator: key name starting with digit must fail
#
# Run with:
#   cd modules/KeyVault-Key
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: RSA key — happy path.
# ---------------------------------------------------------------------
run "rsa_happy" {
  command = plan

  variables {
    keys = {
      cmk_rsa = {
        name         = "cmk-rsa-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_key.this) == 1
    error_message = "RSA happy path must produce exactly one azurerm_key_vault_key resource."
  }
}

# ---------------------------------------------------------------------
# Test 2: EC key — happy path.
# ---------------------------------------------------------------------
run "ec_happy" {
  command = plan

  variables {
    keys = {
      cmk_ec = {
        name         = "cmk-ec-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "EC"
        curve        = "P-256"
        key_opts     = ["sign", "verify"]
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_key.this) == 1
    error_message = "EC happy path must produce exactly one azurerm_key_vault_key resource."
  }
}

# ---------------------------------------------------------------------
# Test 3: Multi-key — 3 keys in the map (RSA + EC + RSA-HSM).
# ---------------------------------------------------------------------
run "multi_key_happy" {
  command = plan

  variables {
    keys = {
      cmk_rsa = {
        name         = "cmk-rsa-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]
      }
      cmk_ec = {
        name         = "cmk-ec-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "EC"
        curve        = "P-384"
        key_opts     = ["sign", "verify"]
      }
      cmk_rsa_hsm = {
        name         = "cmk-rsa-hsm-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA-HSM"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]
      }
    }
  }

  assert {
    condition     = length(azurerm_key_vault_key.this) == 3
    error_message = "Multi-key map must produce exactly three azurerm_key_vault_key resources."
  }
}

# ---------------------------------------------------------------------
# Test 4: rotation_policy.automatic with BOTH time_after_creation AND
#         time_before_expiry set — must fail (XOR validator).
# ---------------------------------------------------------------------
run "rotation_xor_both_set_fails" {
  command = plan

  variables {
    keys = {
      bad_rotation = {
        name         = "bad-rotation-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt"]
        rotation_policy = {
          expire_after         = "P2Y"
          notify_before_expiry = "P30D"
          automatic = {
            time_after_creation = "P1Y"
            time_before_expiry  = "P6M"
          }
        }
      }
    }
  }

  expect_failures = [var.keys]
}

# ---------------------------------------------------------------------
# Test 5: rotation_policy.automatic with NEITHER field set — must fail
#         (XOR validator — empty automatic block rejected by Azure).
# ---------------------------------------------------------------------
run "rotation_xor_neither_set_fails" {
  command = plan

  variables {
    keys = {
      empty_automatic = {
        name         = "empty-automatic-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt"]
        rotation_policy = {
          expire_after         = "P2Y"
          notify_before_expiry = "P30D"
          automatic            = {}
        }
      }
    }
  }

  expect_failures = [var.keys]
}

# ---------------------------------------------------------------------
# Test 6: invalid key_opts value — must fail (key_opts validator).
# ---------------------------------------------------------------------
run "invalid_key_opts_fails" {
  command = plan

  variables {
    keys = {
      bad_opts = {
        name         = "bad-opts-key"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["badop"]
      }
    }
  }

  expect_failures = [var.keys]
}

# ---------------------------------------------------------------------
# Test 7: invalid key_vault_id — must fail (key_vault_id regex validator).
# ---------------------------------------------------------------------
run "invalid_key_vault_id_fails" {
  command = plan

  variables {
    keys = {
      bad_kv_id = {
        name         = "bad-kvid-key"
        key_vault_id = "not-an-ARM-id"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt"]
      }
    }
  }

  expect_failures = [var.keys]
}

# ---------------------------------------------------------------------
# Test 8: key name starting with digit — must fail (key name validator).
# ---------------------------------------------------------------------
run "invalid_key_name_fails" {
  command = plan

  variables {
    keys = {
      bad_name = {
        name         = "1badname"
        key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        key_type     = "RSA"
        key_size     = 2048
        key_opts     = ["encrypt", "decrypt"]
      }
    }
  }

  expect_failures = [var.keys]
}
