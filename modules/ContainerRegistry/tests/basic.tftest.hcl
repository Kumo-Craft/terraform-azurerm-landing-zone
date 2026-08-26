# Plan-time tests for the ContainerRegistry module.
#
# Mocks azurerm + time. Covers:
#   1.  happy_default_naming             — cr{acr}{env}{region}{workload} slug verified
#   2.  happy_name_override              — var.name set wins
#   3.  happy_secure_defaults            — admin_enabled=false, public_network_access_enabled=false,
#                                          anonymous_pull_enabled=false defaults
#   4.  happy_with_lock                  — var.lock = { kind = "CanNotDelete" } wires module.lock
#   5.  happy_with_role_assignments      — for_each RBAC composition plans cleanly (F-1 verification)
#   6.  happy_created_on_tag_present     — CreatedOn tag injected on ACR resource
#   7.  validator_invalid_workload       — bad workload regex rejected
#   8.  validator_invalid_lock_kind      — bad lock kind rejected
#   9.  validator_invalid_principal_type — bad RBAC principal_type rejected
#   10. validator_premium_required_for_cmk — CMK without Premium SKU rejected
#
# Run with:
#   cd modules/ContainerRegistry
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "acr001"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-acr"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming resolves correctly.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.name == "crapiprodgwcacr001"
    error_message = "ACR name must follow the cr{sub}{env}{region}{workload} convention (no hyphens)."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "crlegacy001"
  }

  assert {
    condition     = azurerm_container_registry.this.name == "crlegacy001"
    error_message = "ACR name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_secure_defaults — security baseline defaults verified.
# -----------------------------------------------------------------------
run "happy_secure_defaults" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "admin_enabled must default to false (security baseline)."
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled must default to false (security baseline)."
  }

  assert {
    condition     = azurerm_container_registry.this.anonymous_pull_enabled == false
    error_message = "anonymous_pull_enabled must default to false (security baseline)."
  }

  # CKV_AZURE_233: registry is zone-redundant by default on the Premium-default SKU.
  assert {
    condition     = azurerm_container_registry.this.zone_redundancy_enabled == true
    error_message = "zone_redundancy_enabled must default to true on Premium (CKV_AZURE_233 secure baseline)."
  }

  # export_policy_enabled defaults to false (secure-by-default artifact export lockdown).
  assert {
    condition     = azurerm_container_registry.this.export_policy_enabled == false
    error_message = "export_policy_enabled must default to false (secure baseline)."
  }

  # CKV_AZURE_164 / CKV_AZURE_166: these controls are intentionally NOT defaulted on
  # (DCT deprecated; quarantine is preview and blocks pulls). Assert the deliberate defaults.
  assert {
    condition     = azurerm_container_registry.this.trust_policy_enabled == false
    error_message = "trust_policy_enabled must default to false (DCT deprecated — CKV_AZURE_164 skipped, see main.tf)."
  }

  assert {
    condition     = azurerm_container_registry.this.quarantine_policy_enabled == false
    error_message = "quarantine_policy_enabled must default to false (preview, bricks pulls — CKV_AZURE_166 skipped, see main.tf)."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_lock — var.lock = { kind = "CanNotDelete" } plans cleanly.
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
# Test 5: happy_with_role_assignments — for_each RBAC composition plans cleanly.
# F-1 verification: dropped moved block must NOT cause a plan error.
# -----------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      aks_pull = {
        role_definition_id_or_name = "AcrPull"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = length(module.role_assignments) == 1
    error_message = "One RBAC module instance must be planned when role_assignments has one entry."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_created_on_tag_present — CreatedOn tag injected on ACR.
# -----------------------------------------------------------------------
run "happy_created_on_tag_present" {
  command = plan

  assert {
    condition     = contains(keys(azurerm_container_registry.this.tags), "CreatedOn")
    error_message = "CreatedOn tag must be present in the computed tags map."
  }
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_workload — bad workload regex rejected.
# -----------------------------------------------------------------------
run "validator_invalid_workload" {
  command = plan

  variables {
    workload = "INVALID-WORKLOAD!"
  }

  expect_failures = [var.workload]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_lock_kind — bad lock kind rejected.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "SoftDelete" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_principal_type — bad RBAC principal_type rejected.
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
# Test 10: validator_premium_required_for_cmk — CMK without Premium rejects
# at the resource precondition level.
# Note: The precondition fires on azurerm_container_registry.this, not on
# var.customer_managed_key (which has no SKU context). We pass a non-Premium
# SKU with a CMK set and expect the precondition to fail.
# -----------------------------------------------------------------------
run "validator_premium_required_for_cmk" {
  command = plan

  variables {
    sku = "Standard"
    customer_managed_key = {
      key_vault_key_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv/keys/key/version"
      identity_client_id = "00000000-0000-0000-0000-000000000003"
    }
    identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mi"]
  }

  expect_failures = [azurerm_container_registry.this]
}

# -----------------------------------------------------------------------
# Test 11 (N-8): happy_with_network_rule_set — Premium SKU with
# network_rule_set passed; exercises the ip_rule dynamic block (F-7).
# -----------------------------------------------------------------------
run "happy_with_network_rule_set" {
  command = plan

  variables {
    sku = "Premium"
    network_rule_set = {
      default_action = "Deny"
      ip_rule = [
        { ip_range = "10.0.0.0/8" }
      ]
    }
  }

  assert {
    condition     = azurerm_container_registry.this.sku == "Premium"
    error_message = "SKU must be Premium when network_rule_set is provided."
  }
}

# -----------------------------------------------------------------------
# Test 12 (N-9): happy_with_georeplications — Premium SKU with one
# georeplication entry; exercises the regional_endpoint_enabled attribute
# (F-6).
# -----------------------------------------------------------------------
run "happy_with_georeplications" {
  command = plan

  variables {
    sku = "Premium"
    georeplications = [
      {
        location                  = "westeurope"
        regional_endpoint_enabled = true
      }
    ]
  }

  assert {
    condition     = azurerm_container_registry.this.sku == "Premium"
    error_message = "SKU must be Premium when georeplications is provided."
  }
}

# -----------------------------------------------------------------------
# Test 13 (NF-2): happy_standard_public_access — non-Premium SKU with
# public_network_access_enabled = true must plan cleanly. Guards against
# NF-1: the export/public precondition must NOT fire on non-Premium
# (export_policy_enabled is null-guarded to Premium → never sent to Azure).
# -----------------------------------------------------------------------
run "happy_standard_public_access" {
  command = plan

  variables {
    sku                           = "Standard"
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == true
    error_message = "Standard SKU with public_network_access_enabled = true must plan cleanly (NF-1 regression guard)."
  }
}

# -----------------------------------------------------------------------
# Test 14: happy_private_endpoint — Premium + private_endpoints wires the
# PrivateEndpoint module targeting the "registry" sub-resource.
# -----------------------------------------------------------------------
run "happy_private_endpoint" {
  command = plan

  variables {
    sku = "Premium"

    private_endpoints = {
      primary = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-pe"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"]
      }
    }
  }

  assert {
    condition     = module.private_endpoint["primary"].resources["primary"].private_service_connection[0].subresource_names == tolist(["registry"])
    error_message = "Private Endpoint must target the registry sub-resource."
  }

  assert {
    condition     = module.private_endpoint["primary"].resources["primary"].name == "pe-crapiprodgwcacr001-primary"
    error_message = "PE name must default to pe-{registry_name}-{key}."
  }
}

# -----------------------------------------------------------------------
# Test 15: validator_private_endpoint_requires_premium — PE on a non-Premium
# SKU must fail the precondition.
# -----------------------------------------------------------------------
run "validator_private_endpoint_requires_premium" {
  command = plan

  variables {
    sku = "Standard"

    private_endpoints = {
      primary = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-pe"
      }
    }
  }

  expect_failures = [azurerm_container_registry.this]
}
