# Plan-time tests for the SubnetWithNsg module.
#
# Mocks azurerm + azapi. Covers:
#   1.  happy_default_single_subnet          — minimal single subnet plans cleanly
#   2.  happy_multi_subnet                   — 3 subnets in list
#   3.  happy_with_nat_gateway               — Sprint 4 NAT GW association
#   4.  happy_with_service_endpoints         — Sprint 4 service endpoints
#   5.  happy_with_delegations               — Sprint 4 multi-delegation (delegations field)
#   6.  happy_with_lock_and_rbac             — per-subnet lock + role assignment
#   7.  validator_subnet_name_uniqueness     — duplicate subnet names fails
#   8.  validator_address_prefixes_or_pool   — neither address_prefixes nor ip_address_pool fails
#   9.  validator_private_endpoint_policies_enum  — invalid enum value fails
#  10.  validator_nat_gateway_id_arm_regex   — malformed NAT GW ID fails
#  11.  validator_ip_address_pool_id_regex   — malformed IPAM pool ID fails
#  12.  validator_ip_address_pool_number_positive — number_of_ip_addresses <= 0 fails
#  13.  validator_lock_kind_enum             — invalid lock kind fails
#  14.  validator_role_assignment_principal_type — invalid principal_type fails
#  15.  validator_delegation_dedup           — duplicate delegation names fails (F-8)
#
# Run with:
#   cd modules/SubnetWithNsg
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "azapi" {}

# Shared required inputs reused across all runs.
variables {
  virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc-spoke"

  subnets = [
    {
      name             = "snet-api-prod-gwc-default"
      address_prefixes = ["10.238.1.0/24"]
    }
  ]
}

# -----------------------------------------------------------------------
# Test 1: happy_default_single_subnet — minimal single subnet.
# -----------------------------------------------------------------------
run "happy_default_single_subnet" {
  command = plan

  assert {
    condition     = length(azapi_resource.subnet) == 1
    error_message = "One subnet resource must be planned for a single-entry subnets list."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_multi_subnet — 3 subnets in list.
# -----------------------------------------------------------------------
run "happy_multi_subnet" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        nsg_id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/networkSecurityGroups/nsg-nodes"
      },
      {
        name             = "snet-api-prod-gwc-pe"
        address_prefixes = ["10.238.2.0/24"]
        nsg_id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/networkSecurityGroups/nsg-pe"
      },
      {
        name             = "snet-api-prod-gwc-db"
        address_prefixes = ["10.238.3.0/24"]
      }
    ]
  }

  assert {
    condition     = length(azapi_resource.subnet) == 3
    error_message = "Three subnet resources must be planned for a 3-entry subnets list."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_nat_gateway — Sprint 4 NAT GW association.
# -----------------------------------------------------------------------
run "happy_with_nat_gateway" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        nat_gateway_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/natGateways/ng-api-prod-gwc"
      }
    ]
  }

  assert {
    condition     = length(azapi_resource.subnet) == 1
    error_message = "One subnet with NAT GW association must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_service_endpoints — Sprint 4 service endpoints.
# -----------------------------------------------------------------------
run "happy_with_service_endpoints" {
  command = plan

  variables {
    subnets = [
      {
        name              = "snet-api-prod-gwc-app"
        address_prefixes  = ["10.238.1.0/24"]
        service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      }
    ]
  }

  assert {
    condition     = length(azapi_resource.subnet) == 1
    error_message = "One subnet with service endpoints must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_delegations — Sprint 4 multi-delegation (preferred field).
# Uses flat {name, service_name} shape aligned with Vnet v0.2.57.
# -----------------------------------------------------------------------
run "happy_with_delegations" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-aks"
        address_prefixes = ["10.238.1.0/24"]
        delegations = [
          {
            name         = "aks-delegation"
            service_name = "Microsoft.ContainerService/managedClusters"
          }
        ]
      }
    ]
  }

  assert {
    condition     = length(azapi_resource.subnet) == 1
    error_message = "One subnet with service delegation must be planned."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_with_lock_and_rbac — per-subnet lock + role assignment (v0.2.54 composition).
# -----------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        lock = {
          kind = "CanNotDelete"
          name = "lock-nodes-subnet"
        }
        role_assignments = {
          aks_sp = {
            role_definition_id_or_name = "Network Contributor"
            principal_id               = "00000000-0000-0000-0000-000000000002"
            principal_type             = "ServicePrincipal"
          }
        }
      }
    ]
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry for the locked subnet."
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "RBAC module must plan 1 entry matching the role_assignments map."
  }
}

# -----------------------------------------------------------------------
# Test 7: validator_subnet_name_uniqueness — duplicate subnet names fails.
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
# Test 8: validator_address_prefixes_or_pool — neither set fails.
# -----------------------------------------------------------------------
run "validator_address_prefixes_or_pool" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = []
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 9: validator_private_endpoint_policies_enum — invalid enum value fails.
# -----------------------------------------------------------------------
run "validator_private_endpoint_policies_enum" {
  command = plan

  variables {
    subnets = [
      {
        name                              = "snet-api-prod-gwc-nodes"
        address_prefixes                  = ["10.238.1.0/24"]
        private_endpoint_network_policies = "Invalid"
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 10: validator_nat_gateway_id_arm_regex — malformed NAT GW ID fails.
# -----------------------------------------------------------------------
run "validator_nat_gateway_id_arm_regex" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        nat_gateway_id   = "not-a-valid-arm-id"
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 11: validator_ip_address_pool_id_regex — malformed IPAM pool ID fails.
# -----------------------------------------------------------------------
run "validator_ip_address_pool_id_regex" {
  command = plan

  variables {
    subnets = [
      {
        name = "snet-api-prod-gwc-nodes"
        ip_address_pool = {
          id                     = "not-a-valid-arm-id"
          number_of_ip_addresses = 256
        }
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 12: validator_ip_address_pool_number_positive — number_of_ip_addresses <= 0 fails.
# -----------------------------------------------------------------------
run "validator_ip_address_pool_number_positive" {
  command = plan

  variables {
    subnets = [
      {
        name = "snet-api-prod-gwc-nodes"
        ip_address_pool = {
          id                     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/networkManagers/nm-api-prod/ipamPools/pool-gwc-prod"
          number_of_ip_addresses = 0
        }
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 13: validator_lock_kind_enum — invalid lock kind fails.
# -----------------------------------------------------------------------
run "validator_lock_kind_enum" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        lock = {
          kind = "Bogus"
        }
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 14: validator_role_assignment_principal_type — invalid principal_type fails.
# -----------------------------------------------------------------------
run "validator_role_assignment_principal_type" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-nodes"
        address_prefixes = ["10.238.1.0/24"]
        role_assignments = {
          bad_entry = {
            role_definition_id_or_name = "Network Contributor"
            principal_id               = "00000000-0000-0000-0000-000000000002"
            principal_type             = "Invalid"
          }
        }
      }
    ]
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 15: validator_delegation_dedup — duplicate delegation names fails (F-8).
# Uses both deprecated `delegation` and `delegations` with the same name.
# -----------------------------------------------------------------------
run "validator_delegation_dedup" {
  command = plan

  variables {
    subnets = [
      {
        name             = "snet-api-prod-gwc-aks"
        address_prefixes = ["10.238.1.0/24"]
        delegation = {
          name         = "aks-delegation"
          service_name = "Microsoft.ContainerService/managedClusters"
        }
        delegations = [
          {
            name         = "aks-delegation"
            service_name = "Microsoft.ContainerService/managedClusters"
          }
        ]
      }
    ]
  }

  expect_failures = [var.subnets]
}
