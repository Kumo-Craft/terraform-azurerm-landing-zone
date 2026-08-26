# Plan-time tests for the PostgreSqlFlexible module.
#
# Mocks azurerm. A SQL admin is supplied in shared vars so the admin
# precondition holds for the happy runs.
#
# Run with:
#   cd modules/PostgreSqlFlexible
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-data"

  administrator_login    = "pgadmin"
  administrator_password = "P@ssw0rd-Example-1234!"
}

# 1. convention naming + secure/sane defaults
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.this.name == "psql-mgm-prod-frc-01"
    error_message = "Server name must follow psql-{sub}-{env}-{region}-{workload}."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.version == "16"
    error_message = "postgresql_version must default to 16."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.auto_grow_enabled == true
    error_message = "auto_grow_enabled must default to true."
  }
}

# 2. explicit name override
run "happy_name_override" {
  command = plan

  variables {
    name = "psql-legacy-custom"
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.name == "psql-legacy-custom"
    error_message = "name override must wire through."
  }
}

# 3. Entra auth satisfies the admin precondition without SQL creds
run "happy_entra_auth" {
  command = plan

  variables {
    administrator_login    = null
    administrator_password = null
    authentication = {
      active_directory_auth_enabled = true
      password_auth_enabled         = false
    }
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.authentication[0].active_directory_auth_enabled == true
    error_message = "authentication block must wire active_directory_auth_enabled."
  }
}

# 4. databases + configurations
run "happy_databases_and_config" {
  command = plan

  variables {
    databases      = { app = { charset = "UTF8", collation = "en_US.utf8" } }
    configurations = { require_secure_transport = "on", log_min_duration_statement = "1000" }
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_database.this["app"].name == "app"
    error_message = "Database name must default to the map key."
  }
  assert {
    condition     = length(azurerm_postgresql_flexible_server_configuration.this) == 2
    error_message = "Two server configurations must be planned."
  }
}

# 5. VNet integration wires delegated subnet + private DNS zone
run "happy_vnet_integration" {
  command = plan

  variables {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pg"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.delegated_subnet_id == var.delegated_subnet_id
    error_message = "delegated_subnet_id must wire through."
  }
}

# 6. public-access Private Endpoint (embedded ../PrivateEndpoint)
run "happy_with_private_endpoint" {
  command = plan

  variables {
    private_endpoints = {
      pg = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"]
      }
    }
  }

  assert {
    condition     = length(module.private_endpoint) == 1
    error_message = "One PrivateEndpoint module instance must be planned."
  }
}

# 7. lock + rbac
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One rbac instance must be planned."
  }
  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "One lock entry must be planned."
  }
}

# 8. naming XOR failure
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}

# 9. invalid sku
run "validator_invalid_sku" {
  command = plan

  variables {
    sku_name = "Bogus_D2s_v3"
  }

  expect_failures = [var.sku_name]
}

# 10. invalid version
run "validator_invalid_version" {
  command = plan

  variables {
    postgresql_version = "9"
  }

  expect_failures = [var.postgresql_version]
}

# 11. invalid identity type (SystemAssigned not supported)
run "validator_invalid_identity_type" {
  command = plan

  variables {
    identity = { type = "SystemAssigned", identity_ids = [] }
  }

  expect_failures = [var.identity]
}

# 12. VNet integration without a private DNS zone → precondition failure
run "validator_vnet_requires_dns" {
  command = plan

  variables {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pg"
    private_dns_zone_id = null
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}

# 13. PE + VNet integration together → precondition failure
run "validator_pe_and_vnet_exclusive" {
  command = plan

  variables {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pg"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
    private_endpoints = {
      pg = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
      }
    }
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}

# 14. no admin at all → precondition failure
run "validator_no_admin" {
  command = plan

  variables {
    administrator_login    = null
    administrator_password = null
    authentication         = null
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}

# 15. invalid role principal type
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    role_assignments = {
      bad = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "Foo"
      }
    }
  }

  expect_failures = [var.role_assignments]
}
