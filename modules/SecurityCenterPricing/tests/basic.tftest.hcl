# Plan-time tests for the SecurityCenterPricing module.
#
# Mocks azurerm so `command = plan` needs no Azure credentials.
#
# Covers:
#   1. happy_default    — multiple plans, tier/subplan wired, enabled_plans format
#   2. with_extensions  — CloudPosture Standard with Defender CSPM extensions
#   3. validator_bad_tier — tier not in {Free, Standard} → fail
#   4. validator_empty_extension_name — blank extension name → fail
#   5. secure_default_tier — tier omitted → defaults to "Standard" (Defender ON)
#
# Run with:
#   cd modules/SecurityCenterPricing
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# -----------------------------------------------------------------------
# Test 1: happy_default — tier + subplan pass-through, one resource per key.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  variables {
    plans = {
      VirtualMachines = { tier = "Standard", subplan = "P2" }
      StorageAccounts = { tier = "Standard", subplan = "DefenderForStorageV2" }
      KeyVaults       = { tier = "Free" }
    }
  }

  assert {
    condition     = length(azurerm_security_center_subscription_pricing.this) == 3
    error_message = "One resource must be planned per plans map entry."
  }

  assert {
    condition     = azurerm_security_center_subscription_pricing.this["VirtualMachines"].resource_type == "VirtualMachines" && azurerm_security_center_subscription_pricing.this["VirtualMachines"].tier == "Standard"
    error_message = "resource_type must equal the map key and tier must pass through."
  }

  assert {
    condition     = output.enabled_plans["VirtualMachines"] == "Standard/P2"
    error_message = "enabled_plans must render tier/subplan when a subplan is set."
  }

  assert {
    condition     = output.enabled_plans["KeyVaults"] == "Free"
    error_message = "enabled_plans must render just the tier when no subplan is set."
  }
}

# -----------------------------------------------------------------------
# Test 2: with_extensions — Defender CSPM sub-features.
# -----------------------------------------------------------------------
run "with_extensions" {
  command = plan

  variables {
    plans = {
      CloudPosture = {
        tier = "Standard"
        extension = [
          { name = "AgentlessVmScanning", additional_extension_properties = { ExclusionTags = "[]" } },
          { name = "SensitiveDataDiscovery" },
        ]
      }
    }
  }

  assert {
    condition     = length(azurerm_security_center_subscription_pricing.this["CloudPosture"].extension) == 2
    error_message = "Both extension blocks must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 3: validator_bad_tier — invalid tier → fail.
# -----------------------------------------------------------------------
run "validator_bad_tier" {
  command = plan

  variables {
    plans = {
      VirtualMachines = { tier = "Premium" }
    }
  }

  expect_failures = [var.plans]
}

# -----------------------------------------------------------------------
# Test 5: secure_default_tier — tier omitted → defaults to "Standard".
# Secure-by-default (CKV_AZURE_19): an entry with no explicit tier must
# enable Defender ("Standard"), not fall back to "Free".
# -----------------------------------------------------------------------
run "secure_default_tier" {
  command = plan

  variables {
    plans = {
      KeyVaults = {}
    }
  }

  assert {
    condition     = azurerm_security_center_subscription_pricing.this["KeyVaults"].tier == "Standard"
    error_message = "Omitting tier must default to \"Standard\" (secure-by-default, Defender ON)."
  }
}

# -----------------------------------------------------------------------
# Test 4: validator_empty_extension_name — blank name → fail.
# -----------------------------------------------------------------------
run "validator_empty_extension_name" {
  command = plan

  variables {
    plans = {
      CloudPosture = {
        tier      = "Standard"
        extension = [{ name = "  " }]
      }
    }
  }

  expect_failures = [var.plans]
}
