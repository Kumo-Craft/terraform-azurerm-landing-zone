# Plan-time tests for the Vnet module.
#
# Mocks azurerm + azapi + time. Covers:
#   1.  happy_default_naming              — convention naming resolves correctly
#   2.  happy_name_override               — var.name bypasses naming module
#   3.  happy_with_lock                   — var.lock = { kind = "CanNotDelete" } plans cleanly
#   4.  happy_with_role_assignments       — RBAC entry plans cleanly
#   5.  happy_with_encryption             — var.encryption_enforcement = "DropUnencrypted" plans cleanly
#   6.  happy_with_subnets                — multi-subnet path plans cleanly (NAT GW + NSG + delegation)
#   7.  validator_address_space_xor_pool  — both null fails (F-1 cross-var)
#   8.  validator_subnet_name_uniqueness  — duplicate subnet names fails (F-9)
#   9.  validator_encryption_enum         — invalid encryption_enforcement value fails
#   10. validator_flow_timeout_range      — out-of-range flow_timeout_in_minutes fails
#
# Run with:
#   cd modules/Vnet
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "hub"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-network"
  address_space        = ["10.238.0.0/21"]
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming resolves correctly.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-api-prod-gwc-hub"
    error_message = "VNet name must follow the vnet-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = contains(tolist(azurerm_virtual_network.this.address_space), "10.238.0.0/21")
    error_message = "address_space must be wired through to the resource."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming.
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "vnet-custom-override"
  }

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-custom-override"
    error_message = "VNet name must match the explicit var.name override."
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
# Test 4: happy_with_role_assignments — RBAC entry plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      aks_sp = {
        role_definition_id_or_name = "Network Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000010"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "rbac module must have exactly 1 entry matching the role_assignments map."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_encryption — DropUnencrypted plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_encryption" {
  command = plan

  variables {
    encryption_enforcement = "DropUnencrypted"
  }

  assert {
    condition     = azurerm_virtual_network.this.encryption[0].enforcement == "DropUnencrypted"
    error_message = "encryption.enforcement must be DropUnencrypted when var.encryption_enforcement is set."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_with_subnets — multi-subnet path plans cleanly.
# Includes NAT GW, NSG, and a service delegation.
# -----------------------------------------------------------------------
run "happy_with_subnets" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        nsg_id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/networkSecurityGroups/nsg-nodes"
        nat_gateway_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/natGateways/ng-api-prod-gwc"
        delegations = [
          {
            name         = "aks-delegation"
            service_name = "Microsoft.ContainerService/managedClusters"
          }
        ]
      },
      {
        name             = "snet-api-prod-gwc-db"
        address_prefixes = ["10.238.2.0/24"]
      }
    ]
  }

  assert {
    condition     = length(azapi_resource.subnet) == 2
    error_message = "Two inline subnets must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 7: validator_address_space_xor_pool — both null fails (F-1 cross-var).
# -----------------------------------------------------------------------
run "validator_address_space_xor_pool" {
  command = plan

  variables {
    address_space   = null
    ip_address_pool = null
  }

  expect_failures = [var.address_space]
}

# -----------------------------------------------------------------------
# Test 8: validator_subnet_name_uniqueness — duplicate subnet names fails (F-9).
# -----------------------------------------------------------------------
run "validator_subnet_name_uniqueness" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-duplicate"
        address_prefixes = ["10.238.1.0/24"]
      },
      {
        name             = "snet-duplicate"
        address_prefixes = ["10.238.2.0/24"]
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 9: validator_encryption_enum — invalid value fails.
# -----------------------------------------------------------------------
run "validator_encryption_enum" {
  command = plan

  variables {
    encryption_enforcement = "Invalid"
  }

  expect_failures = [var.encryption_enforcement]
}

# -----------------------------------------------------------------------
# Test 10: validator_flow_timeout_range — out-of-range value fails (F-5).
# -----------------------------------------------------------------------
run "validator_flow_timeout_range" {
  command = plan

  variables {
    flow_timeout_in_minutes = 60
  }

  expect_failures = [var.flow_timeout_in_minutes]
}
