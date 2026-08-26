# Plan-time tests for the ResourceLock module.
#
# These tests run via `terraform test` and only exercise validation logic
# + plan resolution — no real Azure resources are created. They serve as
# a smoke test for the variable shape and validators.
#
# Run locally with:
#   cd ResourceLock
#   terraform init -backend=false
#   terraform test

# ---------------------------------------------------------------------
# Provider mock — required so plan can resolve azurerm without creds.
# ---------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------
# Test 1: enable_locks_on — two entries (RG-scoped + sub-scoped),
#         both keys appear in output.ids.
# ---------------------------------------------------------------------
run "enable_locks_on" {
  command = plan

  variables {
    locks = {
      rg = {
        scope      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
        name       = "lock-rg"
        lock_level = "CanNotDelete"
      }
      sub = {
        scope      = "/subscriptions/00000000-0000-0000-0000-000000000000"
        name       = "lock-sub"
        lock_level = "CanNotDelete"
      }
    }
  }

  assert {
    condition     = length(output.ids) == 2
    error_message = "Expected 2 lock IDs when enable_locks = true and two entries are supplied."
  }

  assert {
    condition     = contains(keys(output.ids), "rg") && contains(keys(output.ids), "sub")
    error_message = "output.ids must contain keys 'rg' and 'sub'."
  }
}

# ---------------------------------------------------------------------
# Test 2: enable_locks_off — two entries with enable_locks = false,
#         output.ids must be empty.
# ---------------------------------------------------------------------
run "enable_locks_off" {
  command = plan

  variables {
    enable_locks = false
    locks = {
      rg = {
        scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
        name  = "lock-rg"
      }
      sub = {
        scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        name  = "lock-sub"
      }
    }
  }

  assert {
    condition     = length(output.ids) == 0
    error_message = "Expected no lock IDs when enable_locks = false."
  }
}

# ---------------------------------------------------------------------
# Test 3: readonly_kind_accepted — ReadOnly lock_level must plan cleanly.
# ---------------------------------------------------------------------
run "readonly_kind_accepted" {
  command = plan

  variables {
    locks = {
      ro = {
        scope      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
        name       = "lock-ro"
        lock_level = "ReadOnly"
      }
    }
  }
}

# ---------------------------------------------------------------------
# Test 4: invalid_lock_level_fails — "Delete" is not a valid level.
# ---------------------------------------------------------------------
run "invalid_lock_level_fails" {
  command = plan

  variables {
    locks = {
      bad = {
        scope      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
        name       = "lock-bad"
        lock_level = "Delete"
      }
    }
  }

  expect_failures = [var.locks]
}

# ---------------------------------------------------------------------
# Test 5: invalid_scope_fails — a non-Azure-ID scope must be rejected.
# ---------------------------------------------------------------------
run "invalid_scope_fails" {
  command = plan

  variables {
    locks = {
      bad = {
        scope = "not-a-scope"
        name  = "lock-bad"
      }
    }
  }

  expect_failures = [var.locks]
}

# ---------------------------------------------------------------------
# Test 6: key_derived_default_name (validates F2) — when no name is
#         provided, the resource name must equal "lock-<map-key>".
# ---------------------------------------------------------------------
run "key_derived_default_name" {
  command = plan

  variables {
    locks = {
      my-rg-lock = {
        scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
      }
    }
  }

  assert {
    condition     = azurerm_management_lock.this["my-rg-lock"].name == "lock-my-rg-lock"
    error_message = "When no name is supplied, lock name must default to 'lock-<map-key>'."
  }
}

# ---------------------------------------------------------------------
# Test 7: name_length_validator_fails (validates F3) — a name longer
#         than 90 characters must be rejected by the variable validator.
# ---------------------------------------------------------------------
run "name_length_validator_fails" {
  command = plan

  variables {
    locks = {
      toolong = {
        scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
        name  = "this-lock-name-is-way-too-long-to-be-valid-because-azure-only-allows-ninety-chars-maximum-x"
      }
    }
  }

  expect_failures = [var.locks]
}

# ---------------------------------------------------------------------
# Test 8: Validator — notes length over Azure 512-char hard limit.
# ---------------------------------------------------------------------
run "notes_length_validator_fails" {
  command = plan

  variables {
    locks = {
      bad = {
        scope      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        lock_level = "CanNotDelete"
        notes      = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
      }
    }
  }

  expect_failures = [var.locks]
}
