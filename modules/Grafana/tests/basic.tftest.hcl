# Plan-time tests for the Grafana module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming_prod        — prod env, no explicit ZR → env-driven true
#   2. happy_default_naming_nprd        — nprd env, no explicit ZR → env-driven false
#   3. happy_explicit_zr_override       — prod env + zone_redundancy_enabled=false → false wins
#   4. happy_name_override              — explicit var.name (XOR escape hatch)
#   5. happy_with_amw_integration       — 2 AMW IDs → 2 integration blocks planned
#   6. happy_with_lock                  — var.lock=CanNotDelete → lock module instantiated
#   7. happy_with_pe                    — subnet_id set → PE planned
#   8. validator_naming_xor_fails       — var.name=null + naming vars null → XOR failure
#   9. validator_invalid_lock_kind      — lock.kind="Bogus" → failure
#
# Run with:
#   cd modules/Grafana
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across most runs.
variables {
  subscription_acronym                = "mgm"
  environment                         = "prod"
  region_code                         = "gwc"
  workload                            = "01"
  location                            = "germanywestcentral"
  resource_group_name                 = "rg-mgm-prod-gwc-grafana"
  user_assigned_identity_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-grafana/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mgm-prod-gwc-grafana"
  user_assigned_identity_principal_id = "00000000-0000-0000-0000-000000000001"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming_prod — prod env, no explicit ZR → env-driven true.
# -----------------------------------------------------------------------
run "happy_default_naming_prod" {
  command = plan

  assert {
    condition     = azurerm_dashboard_grafana.this.zone_redundancy_enabled == true
    error_message = "zone_redundancy_enabled must be true (env-driven) for environment=='prod' when var.zone_redundancy_enabled is null."
  }

  assert {
    condition     = azurerm_dashboard_grafana.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled must default to false (secure-by-default)."
  }

  assert {
    condition     = azurerm_dashboard_grafana.this.resource_group_name == "rg-mgm-prod-gwc-grafana"
    error_message = "resource_group_name must match the caller-provided var.resource_group_name."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_default_naming_nprd — nprd env, no explicit ZR → env-driven false.
# -----------------------------------------------------------------------
run "happy_default_naming_nprd" {
  command = plan

  variables {
    environment = "nprd"
  }

  assert {
    condition     = azurerm_dashboard_grafana.this.zone_redundancy_enabled == false
    error_message = "zone_redundancy_enabled must be false (env-driven) for environment!='prod' when var.zone_redundancy_enabled is null."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_explicit_zr_override — prod env + explicit false → false wins.
# -----------------------------------------------------------------------
run "happy_explicit_zr_override" {
  command = plan

  variables {
    zone_redundancy_enabled = false
  }

  assert {
    condition     = azurerm_dashboard_grafana.this.zone_redundancy_enabled == false
    error_message = "Explicit zone_redundancy_enabled=false must override the prod env-driven default of true."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_name_override — explicit var.name bypasses naming module.
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "amg-custom"
  }

  assert {
    condition     = azurerm_dashboard_grafana.this.name == "amg-custom"
    error_message = "Grafana name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_amw_integration — 2 AMW IDs → 2 integration blocks.
# -----------------------------------------------------------------------
run "happy_with_amw_integration" {
  command = plan

  variables {
    azure_monitor_workspace_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Monitor/accounts/amw-mgm-prod-gwc-01",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitor/providers/Microsoft.Monitor/accounts/amw-mgm-prod-gwc-02"
    ]
  }

  assert {
    condition     = length(azurerm_dashboard_grafana.this.azure_monitor_workspace_integrations) == 2
    error_message = "Exactly 2 AMW integration blocks must be planned when 2 IDs are provided."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_with_lock — lock=CanNotDelete → module.lock instantiated.
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
# Test 7: happy_with_pe — subnet_id set → PE planned.
# -----------------------------------------------------------------------
run "happy_with_pe" {
  command = plan

  variables {
    private_endpoint = {
      subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-gwc/subnets/snet-pe"
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 1
    error_message = "Exactly 1 PE must be planned when private_endpoint is set."
  }
}

# -----------------------------------------------------------------------
# Test 8: validator_naming_xor_fails — name=null + naming vars null → XOR failure.
# -----------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_lock_kind — "Bogus" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}
