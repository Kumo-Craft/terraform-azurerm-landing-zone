# Plan-time tests for the ExpressRouteCircuit module.
#
# Mocks azurerm + time. Covers:
#   - Convention naming (slug "erc" from Azure/naming/azurerm — F-1)
#   - Name override escape hatch
#   - Validator: invalid sku_tier enum (fails)
#   - Validator: Local tier + MeteredData family cross-var (fails)
#   - Validator: invalid bandwidth value (fails)
#   - Validator: BGP ASN in Azure-reserved block (fails)
#   - Validator: VLAN ID out of range (fails)
#   - Validator: non-/30 CIDR prefix (fails)
#
# Run with:
#   cd modules/ExpressRouteCircuit
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Shared variables reused across runs (locals-style via run references)
# ---------------------------------------------------------------------

# Base naming variables used in most runs
variables {
  subscription_acronym  = "con"
  environment           = "prod"
  region_code           = "gwc"
  workload              = "backbone"
  location              = "germanywestcentral"
  resource_group_name   = "rg-network-prod-gwc"
  service_provider_name = "Equinix"
  peering_location      = "Frankfurt"
  bandwidth_in_mbps     = 1000
}

# ---------------------------------------------------------------------
# Test 1: Convention naming — naming vars provided, no var.name.
#         Verifies slug is "erc" and convention output is
#         erc-{acr}-{env}-{region}-{workload}.
# ---------------------------------------------------------------------
run "convention_naming_happy" {
  command = plan

  assert {
    condition     = azurerm_express_route_circuit.this.name == "erc-con-prod-gwc-backbone"
    error_message = "Convention naming must produce erc-{acr}-{env}-{region}-{workload} (slug is 'erc')."
  }
}

# ---------------------------------------------------------------------
# Test 2: Name override — var.name wins over convention when set.
# ---------------------------------------------------------------------
run "name_override_happy" {
  command = plan

  variables {
    name = "er-legacy-name"
  }

  assert {
    condition     = azurerm_express_route_circuit.this.name == "er-legacy-name"
    error_message = "Explicit var.name must override the computed convention name."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validator — invalid sku_tier value.
#         sku_tier must be one of: Basic, Standard, Premium, Local.
# ---------------------------------------------------------------------
run "invalid_sku_tier_fails" {
  command = plan

  variables {
    sku_tier = "InvalidTier"
  }

  expect_failures = [var.sku_tier]
}

# ---------------------------------------------------------------------
# Test 4: Validator — Local tier + MeteredData family cross-var check.
#         Local SKU requires UnlimitedData; MeteredData is rejected by Azure API.
# ---------------------------------------------------------------------
run "local_tier_with_metered_family_fails" {
  command = plan

  variables {
    sku_tier   = "Local"
    sku_family = "MeteredData"
  }

  expect_failures = [var.sku_tier]
}

# ---------------------------------------------------------------------
# Test 5: Validator — bandwidth not in enum.
#         Must be one of: 50, 100, 200, 500, 1000, 2000, 5000, 10000.
# ---------------------------------------------------------------------
run "invalid_bandwidth_fails" {
  command = plan

  variables {
    bandwidth_in_mbps = 300
  }

  expect_failures = [var.bandwidth_in_mbps]
}

# ---------------------------------------------------------------------
# Test 6: Validator — BGP peer ASN in Azure-reserved block (65515).
#         private_peering.peer_asn cannot use reserved ASNs.
# ---------------------------------------------------------------------
run "bgp_asn_reserved_fails" {
  command = plan

  variables {
    private_peering = {
      peer_asn                      = 65515
      primary_peer_address_prefix   = "10.0.1.0/30"
      secondary_peer_address_prefix = "10.0.1.4/30"
      vlan_id                       = 100
    }
  }

  expect_failures = [var.private_peering]
}

# ---------------------------------------------------------------------
# Test 7: Validator — VLAN ID out of 802.1Q range.
#         vlan_id must be 1-4094.
# ---------------------------------------------------------------------
run "vlan_id_out_of_range_fails" {
  command = plan

  variables {
    private_peering = {
      peer_asn                      = 65001
      primary_peer_address_prefix   = "10.0.1.0/30"
      secondary_peer_address_prefix = "10.0.1.4/30"
      vlan_id                       = 5000
    }
  }

  expect_failures = [var.private_peering]
}

# ---------------------------------------------------------------------
# Test 8: Validator — primary prefix not a /30.
#         primary_peer_address_prefix must be a /30 CIDR block.
# ---------------------------------------------------------------------
run "not_a_slash_30_fails" {
  command = plan

  variables {
    private_peering = {
      peer_asn                      = 65001
      primary_peer_address_prefix   = "10.0.0.0/29"
      secondary_peer_address_prefix = "10.0.1.4/30"
      vlan_id                       = 100
    }
  }

  expect_failures = [var.private_peering]
}
