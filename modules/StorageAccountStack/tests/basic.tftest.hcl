# Plan-time tests for the StorageAccountStack module.
#
# Mocks azurerm + time so plan can resolve without credentials.
# The Stack composes ../StorageAccount and ../PrivateEndpoint; these
# tests exercise the wiring (naming + one PE per sub-resource +
# PE→SA resource_id link + validators).
#
# Run with:
#   cd modules/StorageAccountStack
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "time" {}

variables {
  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "data"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-data"
  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"
}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — default { blob = {} } => one blob PE,
#         storage name st{acr}{env}{region}{workload}.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  assert {
    condition     = output.name == "stapiprodgwcdata"
    error_message = "Storage name must follow st{acr}{env}{region}{workload}."
  }

  assert {
    condition     = module.pe["blob"].resources["this"].name == "pep-api-prod-gwc-st-data-blob"
    error_message = "PE name must follow pep-{acr}-{env}-{region}-st-{workload}-{subresource}."
  }

  assert {
    condition     = module.pe["blob"].resources["this"].private_service_connection[0].subresource_names == tolist(["blob"])
    error_message = "Default PE must target the blob sub-resource."
  }
}

# ---------------------------------------------------------------------
# Test 2: Multiple sub-resources — blob + file => two PE instances.
# ---------------------------------------------------------------------
run "multiple_subresources" {
  command = plan

  variables {
    private_endpoints = {
      blob = { private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"] }
      file = { private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"] }
    }
  }

  assert {
    condition     = length(module.pe) == 2
    error_message = "One PrivateEndpoint module instance must be created per sub-resource."
  }

  assert {
    condition     = module.pe["file"].resources["this"].private_service_connection[0].subresource_names == tolist(["file"])
    error_message = "The file PE must target the file sub-resource."
  }
}

# ---------------------------------------------------------------------
# Test 3: No Private Endpoint — empty map => zero PE instances.
# ---------------------------------------------------------------------
run "no_private_endpoint" {
  command = plan

  variables {
    private_endpoints = {}
  }

  assert {
    condition     = length(module.pe) == 0
    error_message = "An empty private_endpoints map must create no Private Endpoints."
  }
}

# ---------------------------------------------------------------------
# Test 4: Validator — unknown sub-resource key must fail.
# ---------------------------------------------------------------------
run "invalid_subresource_fails" {
  command = plan

  variables {
    private_endpoints = {
      nope = {}
    }
  }

  expect_failures = [var.private_endpoints]
}

# ---------------------------------------------------------------------
# Test 5: Validator — bad subnet_id format must fail.
# ---------------------------------------------------------------------
run "invalid_subnet_id_fails" {
  command = plan

  variables {
    subnet_id = "not-a-valid-subnet-id"
  }

  expect_failures = [var.subnet_id]
}
