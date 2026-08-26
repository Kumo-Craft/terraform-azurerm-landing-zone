# Plan-time tests for the PrivateEndpoint module.
#
# Run with:
#   cd modules/PrivateEndpoint
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Multi-PE map — two entries produce two `ids` outputs.
# ---------------------------------------------------------------------
run "multi_pe_map" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      kv = {
        name              = "pep-api-prod-gwc-kv"
        resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-data/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-apim"
        subresource_names = ["vault"]
      }
      st = {
        name              = "pep-api-prod-gwc-st"
        resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-data/providers/Microsoft.Storage/storageAccounts/stapiprodgwcblob"
        subresource_names = ["blob"]
      }
    }
  }

  assert {
    condition     = length(output.ids) == 2
    error_message = "Two PE map entries must produce two ids."
  }

  assert {
    condition     = azurerm_private_endpoint.this["kv"].private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "KV entry must wire subresource_names = [\"vault\"]."
  }
}

# ---------------------------------------------------------------------
# Test 2: F1.1 — resource_alias path (Private Link Service alias)
#         Should plan cleanly with `resource_id = null` and
#         `subresource_names = []`.
# ---------------------------------------------------------------------
run "resource_alias_path" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      pls = {
        name = "pep-api-prod-gwc-pls"
        # Azure PLS alias format: <name>.<guid>.<region>.azure.privatelinkservice
        resource_alias = "mypls.00000000-0000-0000-0000-000000000000.germanywestcentral.azure.privatelinkservice"
      }
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this["pls"].private_service_connection[0].private_connection_resource_alias == "mypls.00000000-0000-0000-0000-000000000000.germanywestcentral.azure.privatelinkservice"
    error_message = "resource_alias must wire to private_connection_resource_alias on the provider."
  }
}

# ---------------------------------------------------------------------
# Test 3: F1.1 validator — neither resource_id nor resource_alias set.
# ---------------------------------------------------------------------
run "neither_id_nor_alias_fails" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      broken = {
        name              = "pep-broken"
        subresource_names = ["vault"]
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

# ---------------------------------------------------------------------
# Test 4: F1.1 validator — BOTH resource_id AND resource_alias set.
# ---------------------------------------------------------------------
run "both_id_and_alias_fails" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      broken = {
        name              = "pep-broken"
        resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
        resource_alias    = "com.microsoft.example.alias"
        subresource_names = ["vault"]
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

# ---------------------------------------------------------------------
# Test 5: F1.2 validator — resource_id set but subresource_names empty.
# ---------------------------------------------------------------------
run "resource_id_without_subresource_names_fails" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      broken = {
        name        = "pep-broken"
        resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
        # subresource_names not provided → defaults to []
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

# ---------------------------------------------------------------------
# Test 6: Manual connection — request_message required when
#         is_manual_connection = true.
# ---------------------------------------------------------------------
run "manual_connection_without_request_message_fails" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      manual = {
        name                 = "pep-manual"
        resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
        subresource_names    = ["vault"]
        is_manual_connection = true
        # request_message intentionally omitted
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

# ---------------------------------------------------------------------
# Test 7: DNS zone group wiring.
# ---------------------------------------------------------------------
run "dns_zone_group_wired" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-net"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"

    private_endpoints = {
      kv = {
        name              = "pep-api-prod-gwc-kv"
        resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-data/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-apim"
        subresource_names = ["vault"]
        private_dns_zone_group = {
          private_dns_zone_ids = [
            "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
          ]
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.this["kv"].private_dns_zone_group) == 1
    error_message = "private_dns_zone_group must be wired when the entry sets it."
  }
}
