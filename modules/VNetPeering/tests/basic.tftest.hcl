# Plan-time tests for the VNetPeering module.
#
# Mocks azurerm. Covers the 2 input validators on var.peerings
# (remote VNet ID format, subnet-scoped vs full-VNet cross-constraint)
# plus happy-path single, bidirectional pair, and subnet-scoped peering.
#
# Run with:
#   cd modules/VNetPeering
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# ---------------------------------------------------------------------
# Test 1: Happy path — single peering with defaults.
#         The peering name equals the map key.
# ---------------------------------------------------------------------
run "happy_path_single_peering" {
  command = plan

  variables {
    peerings = {
      spoke-to-hub = {
        virtual_network_name      = "vnet-spoke"
        resource_group_name       = "rg-spoke-prod-gwc-network"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      }
    }
  }

  assert {
    condition     = azurerm_virtual_network_peering.this["spoke-to-hub"].name == "spoke-to-hub"
    error_message = "The peering resource name must equal the map key."
  }
}

# ---------------------------------------------------------------------
# Test 2: Bidirectional pair — two entries with gateway flags set
#         to the complementary pattern (hub has transit, spoke uses it).
# ---------------------------------------------------------------------
run "bidirectional_pair_ok" {
  command = plan

  variables {
    peerings = {
      spoke-to-hub = {
        virtual_network_name      = "vnet-spoke"
        resource_group_name       = "rg-spoke-prod-gwc-network"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        allow_gateway_transit     = false
        use_remote_gateways       = true
      }
      hub-to-spoke = {
        virtual_network_name      = "vnet-hub"
        resource_group_name       = "rg-hub-prod-gwc-network"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
        allow_gateway_transit     = true
        use_remote_gateways       = false
      }
    }
  }

  assert {
    condition     = length(output.ids) == 2
    error_message = "Two map entries must produce two peering IDs."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validator — remote_virtual_network_id must be a valid
#         Azure resource ID; a plain string must fail.
# ---------------------------------------------------------------------
run "invalid_remote_vnet_id_fails" {
  command = plan

  variables {
    peerings = {
      spoke-to-hub = {
        virtual_network_name      = "vnet-spoke"
        resource_group_name       = "rg-spoke-prod-gwc-network"
        remote_virtual_network_id = "not-a-resource-id"
      }
    }
  }

  expect_failures = [var.peerings]
}

# ---------------------------------------------------------------------
# Test 4: Validator — supplying local_subnet_names while
#         peer_complete_virtual_networks_enabled = true (default)
#         must be rejected by the cross-var validator.
# ---------------------------------------------------------------------
run "subnet_scoped_with_full_vnet_enabled_fails" {
  command = plan

  variables {
    peerings = {
      spoke-to-hub = {
        virtual_network_name                   = "vnet-spoke"
        resource_group_name                    = "rg-spoke-prod-gwc-network"
        remote_virtual_network_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        peer_complete_virtual_networks_enabled = true
        local_subnet_names                     = ["snet-a"]
      }
    }
  }

  expect_failures = [var.peerings]
}

# ---------------------------------------------------------------------
# Test 5: Subnet-scoped peering — peer_complete_virtual_networks_enabled
#         = false with local and remote subnet lists must plan cleanly.
# ---------------------------------------------------------------------
run "subnet_scoped_peering_ok" {
  command = plan

  variables {
    peerings = {
      spoke-to-hub = {
        virtual_network_name                   = "vnet-spoke"
        resource_group_name                    = "rg-spoke-prod-gwc-network"
        remote_virtual_network_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        peer_complete_virtual_networks_enabled = false
        local_subnet_names                     = ["snet-a"]
        remote_subnet_names                    = ["snet-b"]
      }
    }
  }

  assert {
    condition     = length(output.ids) == 1
    error_message = "Subnet-scoped peering must produce exactly one peering ID."
  }
}

# ---------------------------------------------------------------------
# Test 6: Name override — map key "hub" with an explicit name override
#         "azure-side-name". The Azure-side resource name must equal the
#         override, not the map key.
# ---------------------------------------------------------------------
run "name_override_ok" {
  command = plan

  variables {
    peerings = {
      hub = {
        virtual_network_name      = "vnet-spoke"
        resource_group_name       = "rg-spoke-prod-gwc-network"
        remote_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        name                      = "azure-side-name"
      }
    }
  }

  assert {
    condition     = azurerm_virtual_network_peering.this["hub"].name == "azure-side-name"
    error_message = "The Azure-side peering name must equal the name override, not the map key."
  }
}
