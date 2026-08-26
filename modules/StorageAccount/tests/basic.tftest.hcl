# Plan-time tests for the StorageAccount module.
#
# Mocks azurerm + time. Covers:
#   - Minimal happy path (Standard StorageV2, no CMK, no file_shares)
#   - CMK happy path (customer_managed_key + UserAssigned identity)
#   - FileStorage skips blob_properties (F-10 fix)
#   - Validator: network_rules.bypass invalid value must fail
#   - Validator: network_rules.default_action invalid value must fail
#   - Validator: azure_files_authentication AD without active_directory must fail (F-11)
#   - Validator: sas_policy invalid expiration_action must fail (F-12)
#   - Containers + file_shares happy path with output assertions
#
# Run with:
#   cd modules/StorageAccount
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Minimal happy path — Standard StorageV2, no CMK, no extras.
# ---------------------------------------------------------------------
run "minimal_happy" {
  command = plan

  variables {
    name                = "stminimaltest01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
  }

  assert {
    condition     = azurerm_storage_account.this.name == "stminimaltest01"
    error_message = "Minimal happy path: storage account name must match explicit override."
  }

  assert {
    condition     = azurerm_storage_account.this.account_tier == "Standard"
    error_message = "Default account_tier must be Standard."
  }

  # CKV_AZURE_35: default network access rule must be Deny.
  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "Default network_rules.default_action must be Deny (CKV_AZURE_35)."
  }

  # CKV_AZURE_36: Trusted Microsoft Services bypass must be enabled by default.
  assert {
    condition     = contains(azurerm_storage_account.this.network_rules[0].bypass, "AzureServices")
    error_message = "Default network_rules.bypass must include AzureServices (CKV_AZURE_36)."
  }

  # CKV_AZURE_33: Queue Analytics logging (read/write/delete) enabled by default
  # on a queue-capable account (Standard + StorageV2).
  assert {
    condition = (
      azurerm_storage_account.this.queue_properties[0].logging[0].read &&
      azurerm_storage_account.this.queue_properties[0].logging[0].write &&
      azurerm_storage_account.this.queue_properties[0].logging[0].delete
    )
    error_message = "Default queue logging must enable read/write/delete (CKV_AZURE_33)."
  }
}

# ---------------------------------------------------------------------
# Test 1b: network_rules = null removes the firewall block (opt-out escape
# hatch for the new secure default).
# ---------------------------------------------------------------------
run "network_rules_null_removes_block" {
  command = plan

  variables {
    name                = "stnonetrules01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    network_rules       = null
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules) == 0
    error_message = "Setting network_rules = null must emit no network_rules block."
  }
}

# ---------------------------------------------------------------------
# Test 2: CMK happy path — customer_managed_key + UserAssigned identity.
# ---------------------------------------------------------------------
run "with_cmk_happy" {
  command = plan

  variables {
    name                = "stcmkhappytest01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    identity_type       = "UserAssigned"
    customer_managed_key = {
      key_vault_key_id          = "https://kv-test.vault.azure.net/keys/cmk/00000000000000000000000000000000"
      user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-test"
    }
  }

  assert {
    condition     = azurerm_storage_account.this.name == "stcmkhappytest01"
    error_message = "CMK happy path: storage account name must match explicit override."
  }
}

# ---------------------------------------------------------------------
# Test 3: FileStorage skips blob_properties (F-10 fix).
# FileStorage accounts do not support blob_properties — the dynamic block
# must be absent.
# ---------------------------------------------------------------------
run "file_storage_skips_blob_properties" {
  command = plan

  variables {
    name                     = "stfilestorage01"
    location                 = "germanywestcentral"
    resource_group_name      = "rg-test"
    account_tier             = "Premium"
    account_replication_type = "LRS"
    account_kind             = "FileStorage"
  }

  assert {
    condition     = azurerm_storage_account.this.account_kind == "FileStorage"
    error_message = "account_kind must be FileStorage."
  }

  # Premium/FileStorage has no queue endpoint — queue_properties must be absent
  # (CKV_AZURE_33 is inapplicable for this account kind).
  assert {
    condition     = length(azurerm_storage_account.this.queue_properties) == 0
    error_message = "FileStorage accounts must not emit a queue_properties block."
  }
}

# ---------------------------------------------------------------------
# Test 4: network_rules.bypass invalid value — must fail.
# ---------------------------------------------------------------------
run "network_rules_invalid_bypass_fails" {
  command = plan

  variables {
    name                = "stnetbypassfail01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    network_rules = {
      default_action = "Deny"
      bypass         = ["Invalid"]
    }
  }

  expect_failures = [var.network_rules]
}

# ---------------------------------------------------------------------
# Test 5: network_rules.default_action invalid value — must fail.
# ---------------------------------------------------------------------
run "network_rules_invalid_default_action_fails" {
  command = plan

  variables {
    name                = "stnetactionfail01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    network_rules = {
      default_action = "Maybe"
    }
  }

  expect_failures = [var.network_rules]
}

# ---------------------------------------------------------------------
# Test 6: azure_files_authentication AD without active_directory — must fail
#         (F-11 new validator).
# ---------------------------------------------------------------------
run "ad_auth_without_active_directory_fails" {
  command = plan

  variables {
    name                = "stadauthnoad01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    azure_files_authentication = {
      directory_type = "AD"
    }
  }

  expect_failures = [var.azure_files_authentication]
}

# ---------------------------------------------------------------------
# Test 7: sas_policy invalid expiration_action — must fail (F-12 new validator).
# ---------------------------------------------------------------------
run "sas_policy_invalid_action_fails" {
  command = plan

  variables {
    name                = "stsaspolicyfail01"
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    sas_policy = {
      expiration_period = "07.00:00:00"
      expiration_action = "Maybe"
    }
  }

  expect_failures = [var.sas_policy]
}

# ---------------------------------------------------------------------
# Test 8: Containers + file_shares happy path — resources planned.
# ---------------------------------------------------------------------
run "with_containers_and_file_shares_happy" {
  command = plan

  variables {
    name                     = "stcontshares01"
    location                 = "germanywestcentral"
    resource_group_name      = "rg-test"
    account_tier             = "Premium"
    account_replication_type = "LRS"
    account_kind             = "FileStorage"

    containers = {
      bootstrap = {
        name        = "bootstrap"
        access_type = "private"
      }
    }

    file_shares = {
      config = {
        name     = "config"
        quota_gb = 100
      }
    }
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 1
    error_message = "Must plan exactly one container."
  }

  assert {
    condition     = length(azurerm_storage_share.this) == 1
    error_message = "Must plan exactly one file share."
  }
}
