# Plan-time tests for the DdosProtection module.
#
# Mocks azurerm + time. Covers:
#   1.  happy_default_naming             — ddos-{acr}-{env}-{region}-{workload} slug verified
#   2.  happy_name_override              — var.name set wins (F-1 regression guard)
#   3.  happy_with_lock                  — var.lock = { kind = "CanNotDelete" } wires module.lock
#   4.  happy_with_role_assignments      — RBAC entry plans cleanly (F-2 verification)
#   5.  happy_created_on_tag_present     — CreatedOn tag present in computed tags
#   6.  validator_invalid_workload       — bad workload regex rejected
#   7.  validator_invalid_lock_kind      — bad lock kind rejected
#   8.  validator_invalid_principal_type — bad RBAC principal_type rejected
#   9.  validator_invalid_region_code    — bad region_code rejected
#   10. validator_invalid_subscription_acronym — bad acronym rejected
#
# Run with:
#   cd modules/DdosProtection
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "network"
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-network"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming resolves correctly.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_network_ddos_protection_plan.this.name == "ddos-con-prod-gwc-network"
    error_message = "DDoS plan name must follow the ddos-{sub}-{env}-{region}-{workload} convention."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# (F-1 regression guard: must NOT error when for_each = toset([]))
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "ddos-legacy-plan"
  }

  assert {
    condition     = azurerm_network_ddos_protection_plan.this.name == "ddos-legacy-plan"
    error_message = "DDoS plan name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_lock — var.lock = { kind = "CanNotDelete" } plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_role_assignments — RBAC entry plans cleanly (F-2).
# -----------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      network_contributor = {
        role_definition_id_or_name = "Network Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One RBAC module instance must be planned when role_assignments has one entry."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_created_on_tag_present — CreatedOn tag injected.
# -----------------------------------------------------------------------
run "happy_created_on_tag_present" {
  command = plan

  assert {
    condition     = contains(keys(azurerm_network_ddos_protection_plan.this.tags), "CreatedOn")
    error_message = "CreatedOn tag must be present in the computed tags map."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_invalid_workload — bad workload regex rejected.
# -----------------------------------------------------------------------
run "validator_invalid_workload" {
  command = plan

  variables {
    workload = "INVALID WORKLOAD!"
  }

  expect_failures = [var.workload]
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_lock_kind — bad lock kind rejected.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "SoftDelete" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_principal_type — bad RBAC principal_type rejected.
# -----------------------------------------------------------------------
run "validator_invalid_principal_type" {
  command = plan

  variables {
    role_assignments = {
      bad_entry = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "ManagedIdentity"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_region_code — bad region_code rejected.
# -----------------------------------------------------------------------
run "validator_invalid_region_code" {
  command = plan

  variables {
    region_code = "WESTEU"
  }

  expect_failures = [var.region_code]
}

# -----------------------------------------------------------------------
# Test 10: validator_invalid_subscription_acronym — bad acronym rejected.
# -----------------------------------------------------------------------
run "validator_invalid_subscription_acronym" {
  command = plan

  variables {
    subscription_acronym = "toolongacronym"
  }

  expect_failures = [var.subscription_acronym]
}
