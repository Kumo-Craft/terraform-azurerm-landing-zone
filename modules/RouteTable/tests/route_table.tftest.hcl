# Plan-time tests for the RouteTable module.
#
# Mocks azurerm + time. Covers:
#   - Convention naming (slug "route" from Azure/naming/azurerm v0.4.3)
#   - Name override escape hatch
#   - VirtualAppliance route happy-path
#   - Internet route happy-path (no IP)
#   - Validator: VirtualAppliance without next_hop_in_ip_address must fail
#   - Validator: non-VirtualAppliance with next_hop_in_ip_address must fail
#   - Validator: duplicate route names must fail
#
# Run with:
#   cd modules/RouteTable
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Convention naming path — slug must be "route", not "rt".
#         Verifies F-1: upstream Azure/naming/azurerm v0.4.3 uses "route".
# ---------------------------------------------------------------------
run "convention_naming_path" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    name                 = null
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"
  }

  assert {
    condition     = azurerm_route_table.this.name == "route-con-prod-gwc-default"
    error_message = "Convention naming must produce route-{acr}-{env}-{region}-{workload} (slug is 'route', not 'rt')."
  }
}

# ---------------------------------------------------------------------
# Test 2: Name override path — var.name wins over computed convention.
# ---------------------------------------------------------------------
run "name_override_path" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    name                 = "rt-custom-name"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"
  }

  assert {
    condition     = azurerm_route_table.this.name == "rt-custom-name"
    error_message = "Explicit var.name must override the computed convention name."
  }
}

# ---------------------------------------------------------------------
# Test 3: VirtualAppliance route with next_hop_in_ip_address — plan OK.
# ---------------------------------------------------------------------
run "virtual_appliance_route_ok" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"

    routes = {
      default_udr = {
        name                   = "default-udr"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.0.0.4"
      }
    }
  }

  assert {
    condition     = azurerm_route_table.this.name == "route-con-prod-gwc-default"
    error_message = "VirtualAppliance route with IP must plan successfully."
  }

  assert {
    condition     = length(azurerm_route.this) == 1
    error_message = "VirtualAppliance route must produce exactly one separate azurerm_route resource."
  }
}

# ---------------------------------------------------------------------
# Test 4: Internet route with no next_hop_in_ip_address — plan OK.
# ---------------------------------------------------------------------
run "internet_route_ok" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"

    routes = {
      internet_egress = {
        name                   = "internet-egress"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "Internet"
        next_hop_in_ip_address = null
      }
    }
  }

  assert {
    condition     = azurerm_route_table.this.name == "route-con-prod-gwc-default"
    error_message = "Internet route without IP must plan successfully."
  }

  assert {
    condition     = length(azurerm_route.this) == 1
    error_message = "Internet route must produce exactly one separate azurerm_route resource."
  }
}

# ---------------------------------------------------------------------
# Test 5: Validator — VirtualAppliance without next_hop_in_ip_address
#         must hit the "required when VirtualAppliance" validator.
# ---------------------------------------------------------------------
run "virtual_appliance_without_ip_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"

    routes = {
      bad_va = {
        name                   = "bad-va"
        address_prefix         = "10.0.0.0/16"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = null
      }
    }
  }

  expect_failures = [var.routes]
}

# ---------------------------------------------------------------------
# Test 6: Validator — non-VirtualAppliance with next_hop_in_ip_address
#         must hit the "must be null for non-VA" validator.
# ---------------------------------------------------------------------
run "non_virtual_appliance_with_ip_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"

    routes = {
      bad_internet = {
        name                   = "bad-internet"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "Internet"
        next_hop_in_ip_address = "1.2.3.4"
      }
    }
  }

  expect_failures = [var.routes]
}

# ---------------------------------------------------------------------
# Test 7: Validator — two routes with the same name must fail.
#         Duplicate route names are rejected at plan time.
# ---------------------------------------------------------------------
run "duplicate_route_names_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"

    routes = {
      route_a = {
        name                   = "shared-name"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "Internet"
        next_hop_in_ip_address = null
      }
      route_b = {
        name                   = "shared-name" # duplicate — must fail
        address_prefix         = "10.0.0.0/16"
        next_hop_type          = "VnetLocal"
        next_hop_in_ip_address = null
      }
    }
  }

  expect_failures = [var.routes]
}

# ---------------------------------------------------------------------
# Test 8: Two separate route resources planned — regression-guards the
#         new separate-resource model (was implicit via inline block).
# ---------------------------------------------------------------------
run "multi_route_separate_resources" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "default"
    location             = "germanywestcentral"
    resource_group_name  = "rg-con-prod-gwc-network"

    routes = {
      default_udr = {
        name                   = "default-udr"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.0.0.4"
      }
      vnetlocal = {
        name                   = "vnet-local"
        address_prefix         = "10.0.0.0/8"
        next_hop_type          = "Internet"
        next_hop_in_ip_address = null
      }
    }
  }

  assert {
    condition     = length(azurerm_route.this) == 2
    error_message = "Two routes in var.routes must produce exactly two separate azurerm_route resources."
  }
}
