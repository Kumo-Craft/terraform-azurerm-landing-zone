# Plan-time tests for the AzureMonitorWorkspace module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming              — convention naming, no PE, no lock, no rbac
#   2. happy_name_override               — explicit var.name (XOR escape hatch, F-1 fix)
#   3. happy_with_pe                     — subnet_id set → PE planned
#   4. happy_with_lock_and_rbac          — var.lock + 1 role_assignment
#   5. happy_public_network_access_true  — public_network_access_enabled = true override
#   6. validator_naming_xor_fails        — var.name = null + all naming vars = null → failure
#   7. validator_invalid_lock_kind       — lock.kind = "Bogus" → failure
#   8. validator_invalid_role_principal  — principal_type = "Foo" → failure
#
# Run with:
#   cd modules/AzureMonitorWorkspace
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-monitor"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, all defaults.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_monitor_workspace.this.name == "amw-mgm-prod-gwc-01"
    error_message = "AMW name must follow the amw-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azurerm_monitor_workspace.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled must default to false (secure-by-default)."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 0
    error_message = "No PE must be planned when subnet_id is null."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch, F-1).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "amw-custom"
  }

  assert {
    condition     = azurerm_monitor_workspace.this.name == "amw-custom"
    error_message = "AMW name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_pe — subnet_id set → PE planned.
# -----------------------------------------------------------------------
run "happy_with_pe" {
  command = plan

  variables {
    subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-gwc/subnets/snet-pe"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 1
    error_message = "Exactly 1 PE must be planned when subnet_id is set."
  }
}

# -----------------------------------------------------------------------
# Test 3b: happy_pe_with_dns_zone_group — subnet_id + private_dns_zone_ids →
# the PE gets an explicit private_dns_zone_group (name "default") wiring the
# regional Managed Prometheus zone, instead of relying on the DINE policy.
# -----------------------------------------------------------------------
run "happy_pe_with_dns_zone_group" {
  command = plan

  variables {
    subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-gwc/subnets/snet-pe"
    private_dns_zone_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.germanywestcentral.prometheus.monitor.azure.com"
    ]
  }

  assert {
    condition     = length(azurerm_private_endpoint.this[0].private_dns_zone_group) == 1
    error_message = "A private_dns_zone_group must be emitted when private_dns_zone_ids is non-empty."
  }

  assert {
    condition     = azurerm_private_endpoint.this[0].private_dns_zone_group[0].name == "default"
    error_message = "The private_dns_zone_group must be named 'default'."
  }

  assert {
    condition     = azurerm_private_endpoint.this[0].private_dns_zone_group[0].private_dns_zone_ids == var.private_dns_zone_ids
    error_message = "private_dns_zone_group.private_dns_zone_ids must wire through var.private_dns_zone_ids."
  }
}

# -----------------------------------------------------------------------
# Test 3c: happy_pe_no_dns_zone_group_by_default — subnet_id set but
# private_dns_zone_ids empty (default) → NO zone group (DINE back-compat).
# -----------------------------------------------------------------------
run "happy_pe_no_dns_zone_group_by_default" {
  command = plan

  variables {
    subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-gwc/subnets/snet-pe"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this[0].private_dns_zone_group) == 0
    error_message = "No private_dns_zone_group must be emitted by default (left to the DINE policy)."
  }
}

# -----------------------------------------------------------------------
# Test 3d: validator_invalid_dns_zone_id — a non private-DNS-zone ID → failure.
# -----------------------------------------------------------------------
run "validator_invalid_dns_zone_id" {
  command = plan

  variables {
    private_dns_zone_ids = ["/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/virtualNetworks/not-a-zone"]
  }

  expect_failures = [var.private_dns_zone_ids]
}

# -----------------------------------------------------------------------
# Test 4: happy_with_lock_and_rbac — lock + 1 role assignment.
# -----------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      "monitoring-reader" = {
        role_definition_id_or_name = "Monitoring Reader"
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
# Test 5: happy_public_network_access_true — caller override of secure default.
# -----------------------------------------------------------------------
run "happy_public_network_access_overridden" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_monitor_workspace.this.public_network_access_enabled == true
    error_message = "public_network_access_enabled must reflect the caller's override value of true."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_naming_xor_fails — name=null + workload=null → XOR failure.
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
# Test 7: validator_invalid_lock_kind — "Bogus" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_role_principal_type — "Foo" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    role_assignments = {
      "bad-entry" = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "Foo"
      }
    }
  }

  expect_failures = [var.role_assignments]
}
