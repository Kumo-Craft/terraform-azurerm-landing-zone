# Plan-time tests for the vwan module.
#
# Mocks azurerm + time. Covers:
#   - Convention naming (slug "vwan" from Azure/naming/azurerm v0.4.3)
#   - Name override escape hatch
#   - XOR validator: neither var.name nor naming vars (fails)
#   - Naming var regex validator (fails on bad subscription_acronym)
#   - Multi-hub with locks happy path
#   - Validator: invalid hub SKU enum (fails)
#   - Validator: invalid hub_routing_preference enum (fails)
#   - Validator: invalid hub lock kind (fails)
#   - Validator: BGP ASN in reserved block (fails)
#   - Validator: VPN link invalid protocol enum (fails)
#
# Run with:
#   cd modules/vwan
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# ---------------------------------------------------------------------
# Test 1: Convention naming — all four naming vars provided, no
#         var.name. Verifies slug is "vwan" and convention output is
#         vwan-{acr}-{env}-{region}-{workload}.
# ---------------------------------------------------------------------
run "convention_naming_happy" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"
    virtual_hubs         = {}
  }

  assert {
    condition     = azurerm_virtual_wan.vwan.name == "vwan-con-prod-gwc-network"
    error_message = "Convention naming must produce vwan-{acr}-{env}-{region}-{workload} (slug is 'vwan')."
  }
}

# ---------------------------------------------------------------------
# Test 2: Name override — var.name wins over convention when set.
# ---------------------------------------------------------------------
run "name_override_happy" {
  command = plan

  variables {
    name                = "vwan-custom-override"
    location            = "germanywestcentral"
    resource_group_name = "rg-vwan-test"
    virtual_hubs        = {}
  }

  assert {
    condition     = azurerm_virtual_wan.vwan.name == "vwan-custom-override"
    error_message = "Explicit var.name must override the computed convention name."
  }
}

# ---------------------------------------------------------------------
# Test 3: XOR validator — neither var.name nor naming vars provided.
#         The validator on var.name fires: requires name != null OR
#         all four naming vars != null.
# ---------------------------------------------------------------------
run "xor_validator_no_inputs_fails" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-vwan-test"
    virtual_hubs        = {}
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 4: Regex validator on subscription_acronym — value contains
#         digits (not pure lowercase letters). Validates the naming var
#         regex guard (^[a-z]{2,5}$).
# ---------------------------------------------------------------------
run "invalid_subscription_acronym_fails" {
  command = plan

  variables {
    subscription_acronym = "con123"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"
    virtual_hubs         = {}
  }

  expect_failures = [var.subscription_acronym]
}

# ---------------------------------------------------------------------
# Test 5: Multi-hub happy path — two hubs, each with a lock.
#         Verifies hub count and hub_lock module resource count.
# ---------------------------------------------------------------------
run "multi_hub_with_lock_happy" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      hub-gwc = {
        address_prefix = "10.10.0.0/23"
        lock = {
          kind = "CanNotDelete"
        }
      }
      hub-weu = {
        address_prefix = "10.20.0.0/23"
        lock = {
          kind = "ReadOnly"
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_virtual_hub.hubs) == 2
    error_message = "Two entries in var.virtual_hubs must produce exactly two azurerm_virtual_hub resources."
  }

  assert {
    condition     = length(module.hub_lock.ids) == 2
    error_message = "Two hubs each with a lock must produce exactly two management lock resources."
  }
}

# ---------------------------------------------------------------------
# Test 6: Validator — invalid hub SKU value.
#         virtual_hubs[*].sku must be Standard or Basic.
# ---------------------------------------------------------------------
run "invalid_hub_sku_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      bad-hub = {
        address_prefix = "10.10.0.0/23"
        sku            = "InvalidSku"
      }
    }
  }

  expect_failures = [var.virtual_hubs]
}

# ---------------------------------------------------------------------
# Test 7: Validator — invalid hub_routing_preference value.
#         Must be one of: ExpressRoute, VpnGateway, ASPath.
# ---------------------------------------------------------------------
run "invalid_hub_routing_preference_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      bad-hub = {
        address_prefix         = "10.10.0.0/23"
        hub_routing_preference = "NotAValue"
      }
    }
  }

  expect_failures = [var.virtual_hubs]
}

# ---------------------------------------------------------------------
# Test 8: Validator — invalid hub lock kind.
#         virtual_hubs[*].lock.kind must be CanNotDelete or ReadOnly.
# ---------------------------------------------------------------------
run "invalid_lock_kind_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      bad-hub = {
        address_prefix = "10.10.0.0/23"
        lock = {
          kind = "InvalidKind"
        }
      }
    }
  }

  expect_failures = [var.virtual_hubs]
}

# ---------------------------------------------------------------------
# Test 9: Validator — BGP peer ASN in Azure-reserved block (65515).
#         bgp_connections[*].peer_asn cannot use reserved ASNs.
#         Validator fires before any resource reference is resolved.
# ---------------------------------------------------------------------
run "bgp_asn_reserved_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    bgp_connections = {
      bad-bgp = {
        virtual_hub_key            = "hub-gwc"
        virtual_hub_connection_key = "conn-nva"
        peer_asn                   = 65515
        peer_ip                    = "10.10.1.4"
      }
    }
  }

  expect_failures = [var.bgp_connections]
}

# ---------------------------------------------------------------------
# Test 10: Validator — VPN link invalid protocol enum.
#          vpn_connections[*].vpn_links[*].protocol must be IKEv2 or IKEv1.
#          Validator fires before any resource reference is resolved.
# ---------------------------------------------------------------------
run "vpn_link_invalid_protocol_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    vpn_connections = {
      bad-conn = {
        vpn_site_key    = "site-onprem"
        virtual_hub_key = "hub-gwc"
        vpn_links = [
          {
            name     = "link-0"
            protocol = "IKEv0"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_connections]
}

# ---------------------------------------------------------------------
# Test 11: Validator — firewall public_ip_count too low (0).
#          virtual_hubs[*].firewall.public_ip_count must be >= 1.
# ---------------------------------------------------------------------
run "validator_firewall_public_ip_count_too_low" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      hub-gwc = {
        address_prefix = "10.10.0.0/23"
        firewall = {
          public_ip_count = 0
        }
      }
    }
  }

  expect_failures = [var.virtual_hubs]
}

# ---------------------------------------------------------------------
# Test 12: Validator — firewall public_ip_count too high (251).
#          virtual_hubs[*].firewall.public_ip_count must be <= 250.
# ---------------------------------------------------------------------
run "validator_firewall_public_ip_count_too_high" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      hub-gwc = {
        address_prefix = "10.10.0.0/23"
        firewall = {
          public_ip_count = 251
        }
      }
    }
  }

  expect_failures = [var.virtual_hubs]
}

# ---------------------------------------------------------------------
# Test 13: Validator — shared_key too short (< 8 characters).
#          vpn_connections[*].vpn_links[*].shared_key must be >= 8 chars.
# ---------------------------------------------------------------------
run "validator_psk_too_short" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    vpn_connections = {
      bad-conn = {
        vpn_site_key    = "site-onprem"
        virtual_hub_key = "hub-gwc"
        vpn_links = [
          {
            name       = "link-0"
            shared_key = "short"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_connections]
}

# ---------------------------------------------------------------------
# Test 14: Validator — vpn_site with no address_cidrs and no bgp.
#          Each vpn_site must have address_cidrs OR at least one link
#          with bgp configured (Azure API rejects neither).
# ---------------------------------------------------------------------
run "validator_vpn_site_no_cidrs_no_bgp" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    vpn_sites = {
      bad-site = {
        virtual_hub_key = "hub-gwc"
        links = [
          {
            name = "link-0"
          }
        ]
      }
    }
  }

  expect_failures = [var.vpn_sites]
}

# ---------------------------------------------------------------------
# Test 15: P2S AAD happy path — vpn_server_configuration with AAD auth
#          + OpenVPN protocol. Verifies the config resource is planned
#          with the aad block and vpn_protocols passed through.
# ---------------------------------------------------------------------
run "vpn_server_config_aad_happy" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    vpn_server_configurations = {
      p2s-aad = {
        vpn_authentication_types = ["AAD"]
        vpn_protocols            = ["OpenVPN"]
        azure_active_directory_authentication = {
          audience = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
          issuer   = "https://sts.windows.net/00000000-0000-0000-0000-000000000000/"
          tenant   = "https://login.microsoftonline.com/00000000-0000-0000-0000-000000000000/"
        }
      }
    }
  }

  assert {
    condition     = azurerm_vpn_server_configuration.configs["p2s-aad"].vpn_protocols == toset(["OpenVPN"])
    error_message = "vpn_protocols must pass through to the VPN Server Configuration."
  }

  assert {
    condition     = length(azurerm_vpn_server_configuration.configs["p2s-aad"].azure_active_directory_authentication) == 1
    error_message = "AAD auth block must be planned when azure_active_directory_authentication is set."
  }
}

# ---------------------------------------------------------------------
# Test 16: Validator — AAD auth type without the aad block.
#          vpn_authentication_types contains "AAD" but
#          azure_active_directory_authentication is null → fails.
# ---------------------------------------------------------------------
run "vpn_server_config_aad_missing_block_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    vpn_server_configurations = {
      bad-aad = {
        vpn_authentication_types = ["AAD"]
      }
    }
  }

  expect_failures = [var.vpn_server_configurations]
}

# ---------------------------------------------------------------------
# Test 17: Validator — invalid vpn_protocols enum.
#          Must only contain IkeV2 / OpenVPN.
# ---------------------------------------------------------------------
run "vpn_server_config_bad_protocol_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    vpn_server_configurations = {
      bad-proto = {
        vpn_protocols = ["OpenVPN", "WireGuard"]
      }
    }
  }

  expect_failures = [var.vpn_server_configurations]
}

# ---------------------------------------------------------------------
# Test 18: Secure-by-default — a hub firewall left unconfigured for
#          threat intelligence gets threat_intel_mode = "Deny"
#          (Alert and deny). Addresses the intent of CKV_AZURE_216.
# ---------------------------------------------------------------------
run "firewall_threat_intel_deny_by_default" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      hub-gwc = {
        address_prefix = "10.10.0.0/23"
        firewall = {
          public_ip_count = 1
        }
      }
    }
  }

  assert {
    condition     = azurerm_firewall.hub_firewalls["hub-gwc"].threat_intel_mode == "Deny"
    error_message = "Hub firewall must default to threat_intel_mode = \"Deny\" (secure by default)."
  }
}

# ---------------------------------------------------------------------
# Test 19: Validator — Basic tier cannot use threat_intel_mode "Deny".
#          Azure Firewall Basic supports alert mode only; the secure
#          "Deny" default must be overridden on Basic.
# ---------------------------------------------------------------------
run "firewall_basic_tier_deny_fails" {
  command = plan

  variables {
    subscription_acronym = "con"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "network"
    location             = "germanywestcentral"
    resource_group_name  = "rg-vwan-test"

    virtual_hubs = {
      hub-gwc = {
        address_prefix = "10.10.0.0/23"
        firewall = {
          sku_tier          = "Basic"
          threat_intel_mode = "Deny"
          public_ip_count   = 1
        }
      }
    }
  }

  expect_failures = [var.virtual_hubs]
}
