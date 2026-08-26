# Plan-time tests for the Ampls module.
#
# Mocks azurerm + time. Covers:
#   1.  happy_default_naming               — slug computed as pls-{acr}-{env}-{region}-{workload}
#   2.  happy_name_override                — var.name bypasses Naming module
#   3.  happy_default_access_modes         — PrivateOnly default (CAF secure-by-default)
#   4.  happy_open_access_modes            — Open accepted by enum validator
#   5.  happy_with_lock                    — var.lock = { kind = "CanNotDelete" } accepted
#   6.  happy_with_role_assignments        — role_assignments map accepted with valid principal_type
#   7.  happy_with_scoped_services         — multi-entry scoped_services map plans cleanly
#   8.  validator_name_xor_naming_comps    — name=null + all naming vars null → fails
#   9.  validator_invalid_ingestion_mode   — enum rejection ("Closed")
#   10. validator_invalid_query_mode       — enum rejection ("Closed")
#   11. validator_scoped_service_id_regex  — bad resource_id rejected
#   12. validator_invalid_lock_kind        — enum rejection (CanNotDelete/ReadOnly only)
#   13. validator_invalid_principal_type   — enum rejection (User/Group/SP/ForeignGroup/Device only)
#
# Run with:
#   cd modules/Ampls
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------------
# Shared required inputs reused across all runs.
# ---------------------------------------------------------------------------
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "management"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-monitoring"

  subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-gwc-001/subnets/snet-pe"

  private_dns_zone_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.monitor.azure.com",
    "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.oms.opinsights.azure.com",
    "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.ods.opinsights.azure.com",
    "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.agentsvc.azure-automation.net",
    "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net",
  ]

  scoped_services = {
    law = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-001"
    }
  }
}

# ---------------------------------------------------------------------------
# Test 1: happy_default_naming — slug computed when all naming vars provided.
# ---------------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_monitor_private_link_scope.this.name == "pls-mgm-prod-gwc-management"
    error_message = "AMPLS name must follow pls-{acr}-{env}-{region}-{workload} convention."
  }
}

# ---------------------------------------------------------------------------
# Test 2: happy_name_override — var.name bypasses naming module.
# ---------------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "pls-custom-override"
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.this.name == "pls-custom-override"
    error_message = "AMPLS name must use var.name when explicitly set."
  }
}

# ---------------------------------------------------------------------------
# Test 3: happy_default_access_modes — PrivateOnly is the secure default.
# ---------------------------------------------------------------------------
run "happy_default_access_modes" {
  command = plan

  assert {
    condition     = azurerm_monitor_private_link_scope.this.ingestion_access_mode == "PrivateOnly"
    error_message = "Default ingestion_access_mode must be PrivateOnly (secure-by-default)."
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.this.query_access_mode == "PrivateOnly"
    error_message = "Default query_access_mode must be PrivateOnly (secure-by-default)."
  }
}

# ---------------------------------------------------------------------------
# Test 4: happy_open_access_modes — Open is a valid enum value.
# ---------------------------------------------------------------------------
run "happy_open_access_modes" {
  command = plan

  variables {
    ingestion_access_mode = "Open"
    query_access_mode     = "Open"
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.this.ingestion_access_mode == "Open"
    error_message = "ingestion_access_mode must accept Open."
  }

  assert {
    condition     = azurerm_monitor_private_link_scope.this.query_access_mode == "Open"
    error_message = "query_access_mode must accept Open."
  }
}

# ---------------------------------------------------------------------------
# Test 5: happy_with_lock — lock = { kind = "CanNotDelete" } accepted.
# ---------------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = var.lock.kind == "CanNotDelete"
    error_message = "lock.kind CanNotDelete must be accepted by the validator."
  }
}

# ---------------------------------------------------------------------------
# Test 6: happy_with_role_assignments — role_assignments map with valid principal_type.
# ---------------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Monitoring Reader"
        principal_id               = "00000000-0000-0000-0000-000000000010"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = var.role_assignments["reader"].principal_type == "Group"
    error_message = "role_assignments must accept Group as principal_type."
  }
}

# ---------------------------------------------------------------------------
# Test 7: happy_with_scoped_services — multi-entry map plans cleanly.
# ---------------------------------------------------------------------------
run "happy_with_scoped_services" {
  command = plan

  variables {
    scoped_services = {
      law = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-001"
      }
      dce = {
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.Insights/dataCollectionEndpoints/dce-mgm-prod-gwc-001"
      }
    }
  }

  assert {
    condition     = length(var.scoped_services) == 2
    error_message = "Two scoped services must be accepted without validation error."
  }
}

# ---------------------------------------------------------------------------
# Test 8: validator_name_xor_naming_comps — name=null + all naming vars null fails.
# ---------------------------------------------------------------------------
run "validator_name_xor_naming_comps" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = null
    environment          = null
    region_code          = null
    workload             = null
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------------
# Test 9: validator_invalid_ingestion_mode — "Closed" is not in the enum.
# ---------------------------------------------------------------------------
run "validator_invalid_ingestion_mode" {
  command = plan

  variables {
    ingestion_access_mode = "Closed"
  }

  expect_failures = [var.ingestion_access_mode]
}

# ---------------------------------------------------------------------------
# Test 10: validator_invalid_query_mode — "Closed" is not in the enum.
# ---------------------------------------------------------------------------
run "validator_invalid_query_mode" {
  command = plan

  variables {
    query_access_mode = "Closed"
  }

  expect_failures = [var.query_access_mode]
}

# ---------------------------------------------------------------------------
# Test 11: validator_scoped_service_id_regex — bad resource_id rejected.
# ---------------------------------------------------------------------------
run "validator_scoped_service_id_regex" {
  command = plan

  variables {
    scoped_services = {
      bad = {
        resource_id = "not-a-valid-arm-id"
      }
    }
  }

  expect_failures = [var.scoped_services]
}

# ---------------------------------------------------------------------------
# Test 12: validator_invalid_lock_kind — "Delete" is not a valid kind.
# ---------------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Delete" }
  }

  expect_failures = [var.lock]
}

# ---------------------------------------------------------------------------
# Test 13: validator_invalid_principal_type — "Admin" is not a valid principal_type.
# ---------------------------------------------------------------------------
run "validator_invalid_principal_type" {
  command = plan

  variables {
    role_assignments = {
      bad = {
        role_definition_id_or_name = "Monitoring Reader"
        principal_id               = "00000000-0000-0000-0000-000000000010"
        principal_type             = "Admin"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# ---------------------------------------------------------------------------
# Test 14: validator_invalid_subscription_acronym — digit in acronym fails regex ^[a-z]{2,5}$.
# ---------------------------------------------------------------------------
run "validator_invalid_subscription_acronym" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = "mg1"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "management"
  }

  expect_failures = [var.subscription_acronym]
}

# ---------------------------------------------------------------------------
# Test 15: validator_invalid_environment — single letter fails regex ^[a-z]{2,4}$.
# ---------------------------------------------------------------------------
run "validator_invalid_environment" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = "mgm"
    environment          = "p"
    region_code          = "gwc"
    workload             = "management"
  }

  expect_failures = [var.environment]
}

# ---------------------------------------------------------------------------
# Test 16: validator_invalid_region_code — digit in code fails regex ^[a-z]{2,5}$.
# ---------------------------------------------------------------------------
run "validator_invalid_region_code" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gw1"
    workload             = "management"
  }

  expect_failures = [var.region_code]
}

# ---------------------------------------------------------------------------
# Test 17: validator_invalid_workload — starts with digit, fails regex ^[a-z][a-z0-9_-]{1,30}$.
# ---------------------------------------------------------------------------
run "validator_invalid_workload" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "1management"
  }

  expect_failures = [var.workload]
}
