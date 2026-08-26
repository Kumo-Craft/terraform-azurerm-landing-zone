# Plan-time tests for the SqlDatabase module.
#
# These tests run via `terraform test` and only exercise validation logic
# + plan resolution — no real Azure resources are created. They serve as
# a smoke test for the variable shape and validators.
#
# Run locally with:
#   cd SqlDatabase
#   terraform init -backend=false
#   terraform test

# ---------------------------------------------------------------------
# Provider mocks — required so plan can resolve azurerm without creds.
# ---------------------------------------------------------------------
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

# ---------------------------------------------------------------------
# Test 1: Smoke test — minimal valid input produces a clean plan and the
# server name follows the {prefix}-{acr}-{env}-{region}-{workload} rule.
# ---------------------------------------------------------------------
run "smoke" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    databases = {
      app = {
        sku_name    = "GP_S_Gen5_2"
        max_size_gb = 32
      }
    }
  }

  assert {
    condition     = output.server_name == "sql-api-prod-gwc-billing"
    error_message = "Computed server name must follow the {prefix}-{acr}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azurerm_mssql_server.this.minimum_tls_version == "1.2"
    error_message = "Minimum TLS version must default to 1.2."
  }

  assert {
    condition     = azurerm_mssql_server.this.public_network_access_enabled == false
    error_message = "Public network access must default to disabled."
  }

  # CKV_AZURE_229 — zone redundancy is opt-in (default false).
  assert {
    condition     = azurerm_mssql_database.this["app"].zone_redundant == false
    error_message = "Databases must default to zone_redundant = false (opt-in / CKV_AZURE_229 skipped)."
  }

  # CKV_AZURE_224 — ledger is opt-in (default false).
  assert {
    condition     = azurerm_mssql_database.this["app"].ledger_enabled == false
    error_message = "Databases must default to ledger_enabled = false (opt-in / CKV_AZURE_224 skipped)."
  }

  # Auditing degrades gracefully: with no destination supplied, no extended
  # auditing policy is created (CKV_AZURE_23/24 remain open until the LZ
  # supplies a Log Analytics workspace or storage endpoint).
  assert {
    condition     = length(azurerm_mssql_server_extended_auditing_policy.this) == 0
    error_message = "Without an auditing destination the extended auditing policy must not be created."
  }
}

# ---------------------------------------------------------------------
# Test 2: Validator — server name too long fails validation.
# ---------------------------------------------------------------------
run "server_name_too_long_fails_validation" {
  command = plan

  variables {
    name                = "sql-this-name-is-definitely-way-too-long-to-be-a-valid-sql-server-name-indeed"
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 3: Validator — invalid database storage_account_type fails.
# ---------------------------------------------------------------------
run "database_invalid_storage_type_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    databases = {
      app = {
        storage_account_type = "Nope"
      }
    }
  }

  expect_failures = [var.databases]
}

# ---------------------------------------------------------------------
# Test 4: Legacy name escape-hatch — explicit `name` bypasses Naming.
# ---------------------------------------------------------------------
run "legacy_name_override" {
  command = plan

  variables {
    name                = "sql-existing-server-01"
    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-existing"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = output.server_name == "sql-existing-server-01"
    error_message = "Legacy name override must pass through unchanged."
  }
}

# ---------------------------------------------------------------------
# Test 5: Firewall — allow Azure services creates the 0.0.0.0 rule.
# ---------------------------------------------------------------------
run "allow_azure_services_rule" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"
    allow_azure_services = true

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = azurerm_mssql_firewall_rule.allow_azure_services[0].start_ip_address == "0.0.0.0"
    error_message = "allow_azure_services must create the special 0.0.0.0 firewall rule."
  }
}

# ---------------------------------------------------------------------
# Test 6: Elastic pool — pool is created and a database is placed in it
# via elastic_pool_key.
# ---------------------------------------------------------------------
run "elastic_pool_with_database" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    elastic_pools = {
      pool-gp = {
        sku = {
          name     = "GP_Gen5"
          tier     = "GeneralPurpose"
          capacity = 4
        }
        per_database_settings = {
          min_capacity = 0
          max_capacity = 2
        }
        max_size_gb = 256
      }
    }

    databases = {
      app1 = { elastic_pool_key = "pool-gp" }
      app2 = { elastic_pool_key = "pool-gp" }
    }
  }

  assert {
    condition     = azurerm_mssql_elasticpool.this["pool-gp"].name == "pool-gp"
    error_message = "Elastic pool must be created with the map key as its name."
  }

  assert {
    condition     = azurerm_mssql_elasticpool.this["pool-gp"].sku[0].tier == "GeneralPurpose"
    error_message = "Elastic pool tier must be set from the sku block."
  }
}

# ---------------------------------------------------------------------
# Test 7: Validator — unknown elastic_pool_key fails.
# ---------------------------------------------------------------------
run "database_unknown_pool_key_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    databases = {
      app1 = { elastic_pool_key = "does-not-exist" }
    }
  }

  expect_failures = [var.databases]
}

# ---------------------------------------------------------------------
# Test 8: Private Endpoint — module wires a PE targeting sub-resource
# "sqlServer" against the server.
# ---------------------------------------------------------------------
run "private_endpoint" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    private_endpoints = {
      primary = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-pe"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"]
      }
    }
  }

  assert {
    condition     = module.private_endpoint["primary"].resources["primary"].private_service_connection[0].subresource_names == tolist(["sqlServer"])
    error_message = "Private Endpoint must target the sqlServer sub-resource."
  }

  assert {
    condition     = module.private_endpoint["primary"].resources["primary"].name == "pe-sql-api-prod-gwc-billing-primary"
    error_message = "Private Endpoint name must default to pe-{server_name}-{key}."
  }
}

# ---------------------------------------------------------------------
# Test 9: Validator — invalid PE subnet_id fails.
# ---------------------------------------------------------------------
run "private_endpoint_invalid_subnet_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    private_endpoints = {
      bad = {
        subnet_id = "not-a-subnet-id"
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

# ---------------------------------------------------------------------
# Test 10: Auditing to Log Analytics — extended auditing policy is created
# with retention >= 90 (CKV_AZURE_23/24) and the master-db diagnostic
# setting is wired for the Azure Monitor route.
# ---------------------------------------------------------------------
run "auditing_to_log_analytics" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    auditing = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law-1"
    }
  }

  assert {
    condition     = azurerm_mssql_server_extended_auditing_policy.this[0].retention_in_days == 90
    error_message = "Auditing retention must default to 90 days (CKV_AZURE_24)."
  }

  assert {
    condition     = azurerm_mssql_server_extended_auditing_policy.this[0].log_monitoring_enabled == true
    error_message = "Log Analytics route must force log_monitoring_enabled = true."
  }

  assert {
    condition     = azurerm_mssql_server_extended_auditing_policy.this[0].enabled == true
    error_message = "Extended auditing policy must be enabled (CKV_AZURE_23)."
  }

  assert {
    condition     = one([for l in azurerm_monitor_diagnostic_setting.sql_audit[0].enabled_log : l.category]) == "SQLSecurityAuditEvents"
    error_message = "Master-db diagnostic setting must enable the SQLSecurityAuditEvents category."
  }
}

# ---------------------------------------------------------------------
# Test 11: Auditing to storage — extended auditing policy is created and
# no master-db diagnostic setting is created (storage route only).
# ---------------------------------------------------------------------
run "auditing_to_storage" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    auditing = {
      storage_endpoint  = "https://auditsa.blob.core.windows.net"
      retention_in_days = 120
    }
  }

  assert {
    condition     = azurerm_mssql_server_extended_auditing_policy.this[0].retention_in_days == 120
    error_message = "Storage auditing retention must pass through the supplied value."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.sql_audit) == 0
    error_message = "Storage-only auditing must not create a master-db diagnostic setting."
  }
}

# ---------------------------------------------------------------------
# Test 12: Validator — auditing retention below 90 days fails (CKV_AZURE_24).
# ---------------------------------------------------------------------
run "auditing_retention_below_90_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    auditing = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law-1"
      retention_in_days          = 30
    }
  }

  expect_failures = [var.auditing]
}

# ---------------------------------------------------------------------
# Test 13: Opt-in secure database path — ledger_enabled and zone_redundant
# can be turned on per-database (CKV_AZURE_224 / CKV_AZURE_229 secure path).
# ---------------------------------------------------------------------
run "database_ledger_and_zone_redundant_optin" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "billing"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-sql"

    entra_administrator = {
      login_username = "sql-admins"
      object_id      = "22222222-2222-2222-2222-222222222222"
    }

    databases = {
      secure = {
        sku_name       = "BC_Gen5_2"
        ledger_enabled = true
        zone_redundant = true
      }
    }
  }

  assert {
    condition     = azurerm_mssql_database.this["secure"].ledger_enabled == true
    error_message = "ledger_enabled must be settable to true (CKV_AZURE_224 secure path)."
  }

  assert {
    condition     = azurerm_mssql_database.this["secure"].zone_redundant == true
    error_message = "zone_redundant must be settable to true (CKV_AZURE_229 secure path)."
  }
}
