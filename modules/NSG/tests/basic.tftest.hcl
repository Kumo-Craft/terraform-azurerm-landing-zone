# Plan-time tests for the NSG module.
#
# Mocks azurerm + time. Covers the 5 input validators on var.nsgs
# (direction enum, access enum, protocol enum, priority range,
# priority uniqueness) plus naming + multi-NSG smoke.
#
# Run with:
#   cd modules/NSG
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Multi-NSG smoke — two NSGs in the map, naming verified.
#         Each key produces nsg-{acr}-{env}-{region}-{key}.
# ---------------------------------------------------------------------
run "multi_nsg_naming" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      nodes = [
        {
          name                       = "AllowSSHFromBastion"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "22"
          source_address_prefix      = "10.0.1.0/24"
          destination_address_prefix = "*"
        }
      ]
      apps = [
        {
          name                       = "AllowHTTPSFromAppGw"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "10.0.2.0/24"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  assert {
    condition     = azurerm_network_security_group.this["nodes"].name == "nsg-api-prod-gwc-nodes"
    error_message = "Convention naming must produce nsg-{acr}-{env}-{region}-{key} for each map entry."
  }

  assert {
    condition     = azurerm_network_security_group.this["apps"].name == "nsg-api-prod-gwc-apps"
    error_message = "Second NSG entry must also follow the convention."
  }

  assert {
    condition     = length(output.ids) == 2
    error_message = "Two map entries must produce two ids."
  }
}

# ---------------------------------------------------------------------
# Test 2: Empty rules list — NSG creates with no security_rule blocks.
# ---------------------------------------------------------------------
run "empty_rules_list" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      empty = []
    }
  }

  assert {
    condition     = azurerm_network_security_group.this["empty"].name == "nsg-api-prod-gwc-empty"
    error_message = "NSG with empty rules list must still be created with the correct name."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validator — invalid direction (must be Inbound|Outbound).
# ---------------------------------------------------------------------
run "invalid_direction_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      bad = [
        {
          name                       = "BadDirection"
          priority                   = 100
          direction                  = "Sideways"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  expect_failures = [var.nsgs]
}

# ---------------------------------------------------------------------
# Test 4: Validator — invalid access (must be Allow|Deny).
# ---------------------------------------------------------------------
run "invalid_access_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      bad = [
        {
          name                       = "BadAccess"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Maybe"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  expect_failures = [var.nsgs]
}

# ---------------------------------------------------------------------
# Test 5: Validator — invalid protocol enum.
# ---------------------------------------------------------------------
run "invalid_protocol_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      bad = [
        {
          name                       = "BadProtocol"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Http"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  expect_failures = [var.nsgs]
}

# ---------------------------------------------------------------------
# Test 6: Validator — priority out of range (must be 100-4096).
# ---------------------------------------------------------------------
run "priority_out_of_range_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      bad = [
        {
          name                       = "TooLow"
          priority                   = 50
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  expect_failures = [var.nsgs]
}

# ---------------------------------------------------------------------
# Test 7: Validator — duplicate priorities within one NSG.
#         (Azure rejects opaquely at apply time; we catch it at plan.)
# ---------------------------------------------------------------------
run "duplicate_priority_within_nsg_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      dups = [
        {
          name                       = "Rule1"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        },
        {
          name                       = "Rule2"
          priority                   = 100 # duplicate within the same NSG
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "80"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  expect_failures = [var.nsgs]
}

# ---------------------------------------------------------------------
# Test 8: Same priority across DIFFERENT NSGs is OK.
#         Validator is scoped to within-NSG, not cross-NSG.
# ---------------------------------------------------------------------
run "same_priority_across_nsgs_ok" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      front = [
        {
          name                       = "RuleA"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
      back = [
        {
          name                       = "RuleB"
          priority                   = 100 # same priority, different NSG — allowed
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "80"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        }
      ]
    }
  }

  assert {
    condition     = length(output.ids) == 2
    error_message = "Two NSGs each with a rule at priority 100 must plan cleanly (validator is within-NSG, not cross-NSG)."
  }
}

# ---------------------------------------------------------------------
# Test 9: Validator — map key with underscore must fail.
#         The house naming convention (enforced by Naming submodule)
#         requires hyphens, not underscores.
# ---------------------------------------------------------------------
run "invalid_underscore_key_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-network"

    nsgs = {
      bad_key = []
    }
  }

  expect_failures = [var.nsgs]
}
