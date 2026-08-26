# Plan-time tests for the NetworkStack module.
#
# Mocks azurerm + azapi + time. Covers:
#   1.  happy_default_naming           — ../Naming delegation: vnet name follows convention
#   2.  happy_vnet_name_override       — var.vnet_name bypasses naming module (F-6 escape hatch)
#   3.  happy_with_subnets_and_nsg     — subnets + NSG composition plans cleanly
#   4.  happy_with_route_table         — create_route_table=true plans cleanly
#   5.  happy_with_peering             — hub_peering wired to ../VNetPeering plans cleanly
#   6.  happy_with_network_watcher     — create_network_watcher=true plans cleanly
#   7.  happy_no_route_table           — create_route_table=false plans cleanly
#   8.  validator_subscription_acronym — invalid subscription_acronym fails
#   9.  validator_environment          — invalid environment fails
#  10.  validator_region_code          — invalid region_code fails
#  11.  validator_workload             — invalid workload fails
#  12.  validator_address_space_empty  — empty vnet_address_space fails
#  13.  validator_encryption_enum      — invalid encryption_enforcement fails
#  14.  validator_flow_timeout_range   — out-of-range flow_timeout_in_minutes fails
#  15.  validator_subnet_cidr          — malformed subnet CIDR fails
#
# Run with:
#   cd modules/NetworkStack
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym   = "api"
  environment            = "prod"
  region_code            = "gwc"
  workload               = "spoke"
  location               = "germanywestcentral"
  resource_group_name    = "rg-api-prod-gwc-network"
  vnet_address_space     = ["10.238.0.0/21"]
  create_network_watcher = false
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — ../Naming delegation resolves to
#         vnet-{sub}-{env}-{region}-{workload} convention.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-api-prod-gwc-spoke"
    error_message = "VNet name must follow the vnet-{sub}-{env}-{region}-{workload} convention via ../Naming."
  }

  assert {
    condition     = contains(tolist(azurerm_virtual_network.this.address_space), "10.238.0.0/21")
    error_message = "vnet_address_space must be wired through to the resource."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_vnet_name_override — var.vnet_name bypasses Naming (F-6 escape hatch).
# -----------------------------------------------------------------------
run "happy_vnet_name_override" {
  command = plan

  variables {
    vnet_name = "vnet-legacy-override"
  }

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-legacy-override"
    error_message = "VNet name must match the explicit var.vnet_name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_subnets_and_nsg — subnets with NSG composition plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_subnets_and_nsg" {
  command = plan

  variables {
    subnets = {
      nodes = {
        cidr       = "10.238.1.0/24"
        create_nsg = true
      }
      pe = {
        cidr       = "10.238.2.0/24"
        create_nsg = false
      }
    }
  }

  assert {
    condition     = length(azapi_resource.subnet) == 2
    error_message = "Two subnet resources must be planned."
  }

  assert {
    condition     = length(module.nsg.ids) == 1
    error_message = "NSG module must plan exactly 1 NSG for the subnet with create_nsg=true."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_route_table — create_route_table=true plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_route_table" {
  command = plan

  variables {
    create_route_table        = true
    default_route_next_hop_ip = "10.0.0.4"
    subnets = {
      default = {
        cidr               = "10.238.1.0/24"
        attach_route_table = true
      }
    }
  }

  assert {
    condition     = length(module.route_table) == 1
    error_message = "Route table module must plan 1 instance when create_route_table=true."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_peering — hub_peering wired to ../VNetPeering.
# -----------------------------------------------------------------------
run "happy_with_peering" {
  command = plan

  variables {
    hub_peering = {
      name                      = "peer-spoke-to-hub"
      remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-con-prod-gwc-hub/providers/Microsoft.Network/virtualNetworks/vnet-con-prod-gwc-hub"
    }
  }

  assert {
    condition     = length(module.hub_peering.ids) == 1
    error_message = "Hub peering module must plan 1 peering entry."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_with_network_watcher — create_network_watcher=true plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_network_watcher" {
  command = plan

  variables {
    create_network_watcher = true
  }

  assert {
    condition     = length(module.network_watcher) == 1
    error_message = "Network watcher module must plan 1 instance when create_network_watcher=true."
  }
}

# -----------------------------------------------------------------------
# Test 7: happy_no_route_table — create_route_table=false plans cleanly.
# -----------------------------------------------------------------------
run "happy_no_route_table" {
  command = plan

  variables {
    create_route_table = false
  }

  assert {
    condition     = length(module.route_table) == 0
    error_message = "Route table module must plan 0 instances when create_route_table=false."
  }
}

# -----------------------------------------------------------------------
# Test 7b: happy_subnet_dedicated_routes — a subnet with `routes` gets a
#          dedicated route table (rt-{prefix}-{key}) holding ONLY those
#          routes (no default 0.0.0.0/0). Entra Domain Services use case.
# -----------------------------------------------------------------------
run "happy_subnet_dedicated_routes" {
  command = plan

  variables {
    create_route_table = false
    subnets = {
      adds = {
        cidr               = "10.238.212.0/27"
        create_nsg         = true
        attach_route_table = false
        routes = {
          to-shared-resolver = {
            address_prefix         = "10.238.204.0/23"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = "10.238.200.36"
          }
        }
      }
    }
  }

  assert {
    condition     = length(module.subnet_route_table) == 1
    error_message = "A subnet with `routes` must plan exactly one dedicated route table."
  }

  assert {
    condition     = module.subnet_route_table["adds"].name == "rt-api-prod-gwc-adds"
    error_message = "Dedicated route table name must be rt-{prefix}-{subnet_key}."
  }

  assert {
    condition     = length(module.subnet_route_table["adds"].route_ids) == 1
    error_message = "Dedicated route table must hold only the declared route(s) — no default 0.0.0.0/0."
  }

  assert {
    condition     = length(module.route_table) == 0
    error_message = "Shared route table must not be created (create_route_table=false)."
  }
}

# -----------------------------------------------------------------------
# Test 7c: validator_routes_and_attach_exclusive — a subnet cannot set
#          both attach_route_table=true and routes.
# -----------------------------------------------------------------------
run "validator_routes_and_attach_exclusive" {
  command = plan

  variables {
    subnets = {
      adds = {
        cidr               = "10.238.212.0/27"
        attach_route_table = true
        routes = {
          to-shared-resolver = {
            address_prefix         = "10.238.204.0/23"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = "10.238.200.36"
          }
        }
      }
    }
  }

  expect_failures = [var.subnets]
}

# -----------------------------------------------------------------------
# Test 8: validator_subscription_acronym — invalid value fails.
# -----------------------------------------------------------------------
run "validator_subscription_acronym" {
  command = plan

  variables {
    subscription_acronym = "UPPER"
  }

  expect_failures = [var.subscription_acronym]
}

# -----------------------------------------------------------------------
# Test 9: validator_environment — invalid value fails.
# -----------------------------------------------------------------------
run "validator_environment" {
  command = plan

  variables {
    environment = "12"
  }

  expect_failures = [var.environment]
}

# -----------------------------------------------------------------------
# Test 10: validator_region_code — invalid value fails.
# -----------------------------------------------------------------------
run "validator_region_code" {
  command = plan

  variables {
    region_code = "GWCC"
  }

  expect_failures = [var.region_code]
}

# -----------------------------------------------------------------------
# Test 11: validator_workload — invalid value fails (starts with digit).
# -----------------------------------------------------------------------
run "validator_workload" {
  command = plan

  variables {
    workload = "1invalid"
  }

  expect_failures = [var.workload]
}

# -----------------------------------------------------------------------
# Test 12: validator_address_space_empty — empty list fails.
# -----------------------------------------------------------------------
run "validator_address_space_empty" {
  command = plan

  variables {
    vnet_address_space = []
  }

  expect_failures = [var.vnet_address_space]
}

# -----------------------------------------------------------------------
# Test 13: validator_encryption_enum — invalid value fails.
# -----------------------------------------------------------------------
run "validator_encryption_enum" {
  command = plan

  variables {
    encryption_enforcement = "Invalid"
  }

  expect_failures = [var.encryption_enforcement]
}

# -----------------------------------------------------------------------
# Test 14: validator_flow_timeout_range — out-of-range value fails.
# -----------------------------------------------------------------------
run "validator_flow_timeout_range" {
  command = plan

  variables {
    flow_timeout_in_minutes = 60
  }

  expect_failures = [var.flow_timeout_in_minutes]
}

# -----------------------------------------------------------------------
# Test 15: validator_subnet_cidr — malformed CIDR fails.
# -----------------------------------------------------------------------
run "validator_subnet_cidr" {
  command = plan

  variables {
    subnets = {
      bad = {
        cidr = "not-a-cidr"
      }
    }
  }

  expect_failures = [var.subnets]
}
