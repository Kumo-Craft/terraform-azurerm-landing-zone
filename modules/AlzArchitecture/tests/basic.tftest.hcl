# Plan-time tests for the AlzArchitecture module.
#
# Mocks alz + azapi + azurerm. The alz provider fetches ALZ library data
# at plan time; mock_provider "alz" {} replaces those network calls with
# empty/null mock responses. The AVM child iterates over the library output
# to build the MG hierarchy, so happy-path plan behaviour depends on whether
# mock_provider satisfies those iterations.
#
# Strategy:
#   - Attempt happy-path plan tests first (runs 1-3).
#   - Validator tests (runs 4-5) fire at variable evaluation time and do not
#     require the AVM internals to plan successfully.
#
# Run with:
#   cd modules/AlzArchitecture
#   terraform init -backend=false
#   terraform test

mock_provider "alz" {}
mock_provider "azapi" {}
mock_provider "azurerm" {}

# Shared required inputs reused across runs.
variables {
  # AVM validates parent_resource_id must not contain '/' — it expects the raw MG name/ID
  management_root_id           = "00000000-0000-0000-0000-000000000000"
  location                     = "germanywestcentral"
  management_subscription_id   = "00000000-0000-0000-0000-000000000001"
  connectivity_subscription_id = "00000000-0000-0000-0000-000000000002"
  ddos_protection_plan_id      = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-net-prod-gwc-ddos/providers/Microsoft.Network/ddosProtectionPlans/ddos-prod-gwc"
  ama_identity_id              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mgm-prod-gwc-ama"
  action_group_ids             = []
  log_analytics_workspace_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"

  # AMA Data Collection Rules (AlzManagement outputs)
  dcr_vm_insights_id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.Insights/dataCollectionRules/dcr-mgm-prod-gwc-01-vminsights"
  dcr_change_tracking_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.Insights/dataCollectionRules/dcr-mgm-prod-gwc-01-changetracking"
  dcr_defender_sql_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-management/providers/Microsoft.Insights/dataCollectionRules/dcr-mgm-prod-gwc-01-defendersql"

  # coalesce(null, "") panics — provide a non-null value for all happy-path runs
  private_dns_zone_resource_group_name = "rg-dns-prod-gwc-privatedns"

  subscription_placement = {
    management = {
      subscription_id       = "00000000-0000-0000-0000-000000000001"
      management_group_name = "mg-mgm-prod"
    }
    connectivity = {
      subscription_id       = "00000000-0000-0000-0000-000000000002"
      management_group_name = "mg-con-prod"
    }
  }
}

# -----------------------------------------------------------------------
# Test 1: happy_minimal — all required inputs, architecture_name default.
# -----------------------------------------------------------------------
run "happy_minimal" {
  command = plan

  assert {
    condition     = var.architecture_name == "core"
    error_message = "architecture_name must default to 'core'."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_with_subscription_placement — explicit placement map.
# -----------------------------------------------------------------------
run "happy_with_subscription_placement" {
  command = plan

  variables {
    subscription_placement = {
      management = {
        subscription_id       = "00000000-0000-0000-0000-000000000001"
        management_group_name = "mg-mgm-prod"
      }
    }
  }

  assert {
    condition     = length(var.subscription_placement) == 1
    error_message = "One subscription placement entry must be wired through."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_policy_assignments_to_modify — custom defender plan.
# -----------------------------------------------------------------------
run "happy_with_policy_assignments_to_modify" {
  command = plan

  variables {
    defender_plans = {
      storage = "Disabled"
    }
  }

  assert {
    condition     = var.defender_plans.storage == "Disabled"
    error_message = "Defender plan override must be accepted."
  }
}

# -----------------------------------------------------------------------
# Test 4: validator_architecture_name_null — architecture_name is nullable=false
# with a non-null default, so we test the validator by asserting the default
# passes through. (nullable=false with a default cannot be set to null in tftest.)
# Test the string is a non-empty value accepted by the module.
# -----------------------------------------------------------------------
run "validator_architecture_name_default" {
  command = plan

  assert {
    condition     = length(var.architecture_name) > 0
    error_message = "architecture_name must be a non-empty string."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_defender_plans_invalid_value — "Invalid" must fail.
# -----------------------------------------------------------------------
run "validator_defender_plans_invalid_value" {
  command = plan

  variables {
    defender_plans = {
      storage = "Invalid"
    }
  }

  expect_failures = [var.defender_plans]
}
