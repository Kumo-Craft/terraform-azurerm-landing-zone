# Plan-time tests for the PrivateDnsZones module.
#
# Mocks azurerm + time so plan can resolve without credentials. The
# module wraps the AVM ptn private-link-private-dns-zones module; these
# tests exercise the wrapper's `virtual_network_links` passthrough and
# the new optional `resolution_policy` attribute (fallback to internet).
#
# Run with:
#   cd modules/PrivateDnsZones
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# The AVM ptn module pulls in the `regions` submodule, which reads
# data.azapi_client_config + azapi_resource_action.locations. Mock azapi
# with a concrete subscription_id so the regions data source builds a
# valid "/subscriptions/<id>" resource_id (a real azapi provider returns
# an empty subscription_id in CI, breaking the plan).
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "00000000-0000-0000-0000-000000000000"
    }
  }
}

# The regions submodule transforms the live ARM "locations" API response
# (data.azapi_resource_action.locations). A mocked azapi returns a null
# output, so supply a concrete minimal locations payload (West Europe) for
# every run. Shape matches what regions/locals.live_data.tf consumes.
override_data {
  target = module.private_dns_zones.module.regions.data.azapi_resource_action.locations[0]
  values = {
    output = {
      value = [
        {
          name        = "westeurope"
          displayName = "West Europe"
          availabilityZoneMappings = [
            { logicalZone = "1", physicalZone = "westeurope-az1" },
            { logicalZone = "2", physicalZone = "westeurope-az2" },
            { logicalZone = "3", physicalZone = "westeurope-az3" },
          ]
          metadata = {
            geography      = "Europe"
            geographyGroup = "Europe"
            regionCategory = "Recommended"
            regionType     = "Physical"
            pairedRegion   = [{ name = "northeurope" }]
          }
        }
      ]
    }
  }
}

variables {
  location            = "westeurope"
  resource_group_name = "rg-con-prod-weu-dns"
  resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-weu-dns"
}

# ---------------------------------------------------------------------
# Test 1: Default link — resolution_policy unset (backward compatible).
# ---------------------------------------------------------------------
run "link_without_resolution_policy" {
  command = plan

  variables {
    virtual_network_links = {
      shared = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-weu-net/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      }
    }
  }

  assert {
    condition     = output.resource_group_name == "rg-con-prod-weu-dns"
    error_message = "Plan must resolve and pass through the resource group name with a link that omits resolution_policy."
  }
}

# ---------------------------------------------------------------------
# Test 2: Fallback to internet — resolution_policy = NxDomainRedirect.
# ---------------------------------------------------------------------
run "link_with_nxdomain_redirect" {
  command = plan

  variables {
    virtual_network_links = {
      shared = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-weu-net/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        resolution_policy           = "NxDomainRedirect"
      }
    }
  }

  assert {
    condition     = output.resource_group_name == "rg-con-prod-weu-dns"
    error_message = "Plan must resolve with resolution_policy = NxDomainRedirect on the link."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validator — invalid resolution_policy must fail at plan time.
# ---------------------------------------------------------------------
run "invalid_resolution_policy_fails" {
  command = plan

  variables {
    virtual_network_links = {
      shared = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-con-prod-weu-net/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        resolution_policy           = "Bogus"
      }
    }
  }

  expect_failures = [var.virtual_network_links]
}
