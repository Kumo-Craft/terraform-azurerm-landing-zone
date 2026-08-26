# Plan-time tests for the NatGateway module.
#
# Mocks azurerm + azapi + time. Covers:
#   1. happy_default_naming          — convention naming, no additional PIPs, no PIP prefixes, no lock, no rbac
#   2. happy_name_override           — explicit var.name override (XOR escape hatch)
#   3. happy_multi_pip               — 3-entry var.additional_public_ips
#   4. happy_with_pip_prefix         — F-5: 1-entry var.public_ip_prefix_ids
#   5. happy_with_lock_and_rbac      — var.lock + 1 role_assignment
#   6. happy_no_zone                 — var.zones = [] (regional, no-zone)
#   7. validator_invalid_zones       — var.zones = ["1","4"] → F-7 validator failure
#   8. validator_invalid_principal   — principal_type = "Bogus" → F-3 validator failure
#   9. validator_too_many_pips       — additional_public_ips with 16 entries → validator failure
#
# Run with:
#   cd modules/NatGateway
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "untrust"
  location             = "germanywestcentral"
  resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-gwc-network"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, all defaults.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azapi_resource.nat_gateway.name == "ng-con-prod-gwc-untrust"
    error_message = "NAT Gateway name must follow the ng-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azapi_resource.public_ip.name == "pip-ng-con-prod-gwc-untrust"
    error_message = "Base PIP name must be pip-<nat-gateway-name>."
  }

  assert {
    condition     = length(azapi_resource.additional_public_ip) == 0
    error_message = "No additional PIPs must be planned when var.additional_public_ips is empty."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "ng-custom"
  }

  assert {
    condition     = azapi_resource.nat_gateway.name == "ng-custom"
    error_message = "NAT Gateway name must match the explicit var.name override."
  }

  assert {
    condition     = azapi_resource.public_ip.name == "pip-ng-custom"
    error_message = "Base PIP name must be pip-ng-custom when var.name is overridden."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_multi_pip — 3 additional PIPs (total 4 with base).
# -----------------------------------------------------------------------
run "happy_multi_pip" {
  command = plan

  variables {
    additional_public_ips = {
      "02" = {}
      "03" = { zones = ["1"] }
      "04" = { zones = ["2"] }
    }
  }

  assert {
    condition     = length(azapi_resource.additional_public_ip) == 3
    error_message = "Exactly 3 additional PIPs must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_pip_prefix — F-5: 1-entry public_ip_prefix_ids.
# -----------------------------------------------------------------------
run "happy_with_pip_prefix" {
  command = plan

  variables {
    public_ip_prefix_ids = {
      "prefix-01" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-gwc-network/providers/Microsoft.Network/publicIPPrefixes/prefix-01"
    }
  }

  assert {
    condition     = length(var.public_ip_prefix_ids) == 1
    error_message = "public_ip_prefix_ids must contain the 1 supplied entry."
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
      "network-contributor" = {
        role_definition_id_or_name = "Network Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One rbac module instance must be planned when 1 role assignment is supplied."
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_no_zone — var.zones = [] (regional, no-zone).
# -----------------------------------------------------------------------
run "happy_no_zone" {
  command = plan

  variables {
    zones = []
  }

  assert {
    condition     = azapi_resource.nat_gateway.name == "ng-con-prod-gwc-untrust"
    error_message = "No-zone regional deployment must plan cleanly."
  }
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_zones — zones containing "4" → F-7 failure.
# -----------------------------------------------------------------------
run "validator_invalid_zones" {
  command = plan

  variables {
    zones = ["1", "4"]
  }

  expect_failures = [var.zones]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_role_principal_type — "Bogus" → F-3 failure.
# -----------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    role_assignments = {
      "bad-entry" = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "Bogus"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# -----------------------------------------------------------------------
# Test 9: validator_too_many_additional_pips — 16 entries → failure.
# -----------------------------------------------------------------------
run "validator_too_many_additional_pips" {
  command = plan

  variables {
    additional_public_ips = {
      "02" = {}, "03" = {}, "04" = {}, "05" = {},
      "06" = {}, "07" = {}, "08" = {}, "09" = {},
      "10" = {}, "11" = {}, "12" = {}, "13" = {},
      "14" = {}, "15" = {}, "16" = {}, "17" = {}
    }
  }

  expect_failures = [var.additional_public_ips]
}
