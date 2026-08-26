# Plan-time tests for the Ipam module.
#
# Mocks azurerm so `command = plan` needs no Azure credentials. The
# Naming submodule's `random` provider runs for real (offline).
#
# Covers:
#   1. happy_minimal       — create AVNM + single root pool, slug naming
#   2. hierarchy           — parent/child pool, parent_pool_name wiring
#   3. byo_network_manager — attach pools to an existing AVNM (no AVNM created)
#   4. static_cidrs        — both static-CIDR forms (prefixes + count)
#   5. validator_byo_no_id       — create=false + no existing id → fail
#   6. validator_scope_required  — create=true + empty scope → fail
#   7. validator_bad_parent      — parent_pool_key points nowhere → fail
#   8. validator_static_cidr_xor — static CIDR sets both forms → fail
#
# Run with:
#   cd modules/Ipam
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs reused across runs.
variables {
  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-ipam"

  network_manager_scope = {
    subscription_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  }

  pools = {
    root = { address_prefixes = ["10.0.0.0/8"] }
  }
}

# -----------------------------------------------------------------------
# Test 1: happy_minimal — AVNM created + one root pool, derived slug name.
# -----------------------------------------------------------------------
run "happy_minimal" {
  command = plan

  assert {
    condition     = length(azurerm_network_manager.this) == 1
    error_message = "One Network Manager must be planned when create_network_manager = true."
  }

  assert {
    condition     = azurerm_network_manager_ipam_pool.root["root"].name == "ipam-root-con-prod-gwc-01"
    error_message = "Pool name must derive as ipam-{key}-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = length(azurerm_network_manager_ipam_pool.child) == 0
    error_message = "A root-only pool set must plan no child pools."
  }
}

# -----------------------------------------------------------------------
# Test 2: hierarchy — child pool references its parent's name.
# -----------------------------------------------------------------------
run "hierarchy" {
  command = plan

  variables {
    pools = {
      root = { address_prefixes = ["10.0.0.0/8"], display_name = "Root" }
      hub  = { address_prefixes = ["10.0.0.0/16"], parent_pool_key = "root" }
    }
  }

  assert {
    condition     = length(azurerm_network_manager_ipam_pool.root) == 1 && length(azurerm_network_manager_ipam_pool.child) == 1
    error_message = "One root and one child pool must be planned."
  }

  assert {
    condition     = azurerm_network_manager_ipam_pool.child["hub"].parent_pool_name == "ipam-root-con-prod-gwc-01"
    error_message = "Child pool parent_pool_name must resolve to the parent pool's name."
  }
}

# -----------------------------------------------------------------------
# Test 3: byo_network_manager — no AVNM created, pool rides existing id.
# -----------------------------------------------------------------------
run "byo_network_manager" {
  command = plan

  variables {
    create_network_manager      = false
    existing_network_manager_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-gwc-net/providers/Microsoft.Network/networkManagers/nm-con-prod-gwc-01"
  }

  assert {
    condition     = length(azurerm_network_manager.this) == 0
    error_message = "No Network Manager must be created when create_network_manager = false."
  }

  assert {
    condition     = azurerm_network_manager_ipam_pool.root["root"].network_manager_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-gwc-net/providers/Microsoft.Network/networkManagers/nm-con-prod-gwc-01"
    error_message = "Pool must attach to the existing Network Manager id."
  }
}

# -----------------------------------------------------------------------
# Test 4: static_cidrs — both allocation forms carved out of a pool.
# -----------------------------------------------------------------------
run "static_cidrs" {
  command = plan

  variables {
    pools = {
      root = {
        address_prefixes = ["10.0.0.0/8"]
        static_cidrs = {
          reserved = { address_prefixes = ["10.0.0.0/24"] }
          block    = { number_of_ip_addresses_to_allocate = "256" }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_network_manager_ipam_pool_static_cidr.this) == 2
    error_message = "Both static CIDRs must be planned."
  }

  assert {
    condition     = azurerm_network_manager_ipam_pool_static_cidr.this["root/block"].number_of_ip_addresses_to_allocate == "256"
    error_message = "Count-based static CIDR must pass number_of_ip_addresses_to_allocate through."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_byo_no_id — create=false with no existing id → fail.
# -----------------------------------------------------------------------
run "validator_byo_no_id" {
  command = plan

  variables {
    create_network_manager      = false
    existing_network_manager_id = null
  }

  expect_failures = [var.existing_network_manager_id]
}

# -----------------------------------------------------------------------
# Test 6: validator_scope_required — create=true but empty scope → fail.
# -----------------------------------------------------------------------
run "validator_scope_required" {
  command = plan

  variables {
    network_manager_scope = {}
  }

  expect_failures = [var.network_manager_scope]
}

# -----------------------------------------------------------------------
# Test 7: validator_bad_parent — parent_pool_key references nothing → fail.
# -----------------------------------------------------------------------
run "validator_bad_parent" {
  command = plan

  variables {
    pools = {
      hub = { address_prefixes = ["10.0.0.0/16"], parent_pool_key = "does-not-exist" }
    }
  }

  expect_failures = [var.pools]
}

# -----------------------------------------------------------------------
# Test 8: validator_static_cidr_xor — both forms set on one CIDR → fail.
# -----------------------------------------------------------------------
run "validator_static_cidr_xor" {
  command = plan

  variables {
    pools = {
      root = {
        address_prefixes = ["10.0.0.0/8"]
        static_cidrs = {
          bad = {
            address_prefixes                   = ["10.0.0.0/24"]
            number_of_ip_addresses_to_allocate = "256"
          }
        }
      }
    }
  }

  expect_failures = [var.pools]
}

# -----------------------------------------------------------------------
# Test 9: validator_three_tier — grandchild (child of a child) → fail.
# -----------------------------------------------------------------------
run "validator_three_tier" {
  command = plan

  variables {
    pools = {
      root       = { address_prefixes = ["10.0.0.0/8"] }
      region     = { address_prefixes = ["10.0.0.0/12"], parent_pool_key = "root" }
      grandchild = { address_prefixes = ["10.0.0.0/16"], parent_pool_key = "region" }
    }
  }

  expect_failures = [var.pools]
}
