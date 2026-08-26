# Plan-time tests for the FinOpsHub module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming         — convention naming + ADX enabled (default)
#   2. happy_name_override          — explicit var.name escape hatch
#   3. happy_data_explorer_disabled — enable_data_explorer=false → no ADX resources
#   4. happy_with_cost_export       — cost_management_exports_principal_id set (count=1, F-3 verify)
#   5. happy_no_cost_export         — cost_management_exports_principal_id=null (count=0)
#   6. validator_naming_xor_fails   — var.name=null + naming vars null → XOR failure
#
# Run with:
#   cd modules/FinOpsHub
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across most runs.
variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "finops"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-finops"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, ADX enabled (default).
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.resource_group_name == "rg-mgm-prod-gwc-finops"
    error_message = "resource_group_name must match the caller-provided value."
  }

  assert {
    condition     = azurerm_storage_account.this.location == "germanywestcentral"
    error_message = "location must match the caller-provided value."
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "min_tls_version must be TLS1_2."
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled must default to false (secure-by-default)."
  }

  assert {
    condition     = azurerm_storage_account.this.local_user_enabled == false
    error_message = "local_user_enabled must default to false (CKV_AZURE_244, secure-by-default)."
  }

  assert {
    condition     = length(azurerm_kusto_cluster.this) == 1
    error_message = "ADX cluster must be planned when enable_data_explorer=true (default)."
  }

  assert {
    condition     = azurerm_kusto_cluster.this[0].disk_encryption_enabled == true
    error_message = "ADX disk_encryption_enabled must default to true (CKV_AZURE_74, secure-by-default)."
  }

  assert {
    condition     = azurerm_kusto_cluster.this[0].double_encryption_enabled == false
    error_message = "ADX double_encryption_enabled must default to false (CKV_AZURE_75 kept opt-in — creation-only ForceNew property)."
  }

  assert {
    condition     = length(module.adx_eventhub_receiver) == 1
    error_message = "ADX → Event Hubs Data Receiver role must be planned when enable_data_explorer=true."
  }
}

# -----------------------------------------------------------------------
# Test 1b: adx_double_encryption_optin — setting the var to true is honored.
# double_encryption_enabled is a creation-only ForceNew property, kept opt-in
# (default false); this verifies the opt-in path still wires through (CKV_AZURE_75).
# -----------------------------------------------------------------------
run "adx_double_encryption_optin" {
  command = plan

  variables {
    adx_double_encryption_enabled = true
  }

  assert {
    condition     = azurerm_kusto_cluster.this[0].double_encryption_enabled == true
    error_message = "ADX double_encryption_enabled must be true when var.adx_double_encryption_enabled=true."
  }

  assert {
    condition     = azurerm_kusto_cluster.this[0].disk_encryption_enabled == true
    error_message = "ADX disk_encryption_enabled must remain true (CKV_AZURE_74) in the double-encryption opt-in path."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "myfinops"
  }

  assert {
    condition     = azurerm_data_factory.this.name == "adf-myfinops"
    error_message = "ADF name must use var.name as suffix with adf- prefix."
  }

  assert {
    condition     = azurerm_storage_account.this.name == "stfhmyfinops"
    error_message = "Storage account name must use stfh prefix + var.name."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_data_explorer_disabled — no ADX/EventHub resources planned.
# -----------------------------------------------------------------------
run "happy_data_explorer_disabled" {
  command = plan

  variables {
    enable_data_explorer = false
  }

  assert {
    condition     = length(azurerm_kusto_cluster.this) == 0
    error_message = "No ADX cluster must be planned when enable_data_explorer=false."
  }

  assert {
    condition     = length(azurerm_eventhub_namespace.this) == 0
    error_message = "No EventHub Namespace must be planned when enable_data_explorer=false."
  }

  assert {
    condition     = length(azurerm_kusto_database.ingestion) == 0
    error_message = "No ADX Ingestion DB must be planned when enable_data_explorer=false."
  }

  assert {
    condition     = length(azurerm_kusto_database_principal_assignment.hub_additional_viewers) == 0
    error_message = "Additional viewers must not be planned when enable_data_explorer=false (even if supplied)."
  }

  assert {
    condition     = length(azurerm_kusto_database_principal_assignment.ingestion_additional_viewers) == 0
    error_message = "Ingestion viewers must not be planned when enable_data_explorer=false (even if supplied)."
  }

  assert {
    condition     = length(module.adx_eventhub_receiver) == 0
    error_message = "ADX → Event Hubs Data Receiver role must not be planned when enable_data_explorer=false."
  }
}

# -----------------------------------------------------------------------
# Test 3b: hub_additional_viewers — one Viewer assignment per entry on the
#          Hub database (e.g. Grafana's identity).
# -----------------------------------------------------------------------
run "hub_additional_viewers" {
  command = plan

  variables {
    hub_additional_viewers = {
      grafana = "11111111-1111-1111-1111-111111111111"
      finops  = "22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = length(azurerm_kusto_database_principal_assignment.hub_additional_viewers) == 2
    error_message = "One Kusto principal assignment must be planned per hub_additional_viewers entry."
  }

  assert {
    condition     = azurerm_kusto_database_principal_assignment.hub_additional_viewers["grafana"].name == "viewer-grafana" && azurerm_kusto_database_principal_assignment.hub_additional_viewers["grafana"].role == "Viewer" && azurerm_kusto_database_principal_assignment.hub_additional_viewers["grafana"].principal_type == "App"
    error_message = "Additional viewer must be name=viewer-{key}, role=Viewer, principal_type=App."
  }

  assert {
    condition     = length(azurerm_kusto_database_principal_assignment.ingestion_additional_viewers) == 2
    error_message = "One Ingestion Viewer assignment must be planned per hub_additional_viewers entry (cross-db access)."
  }

  assert {
    condition     = azurerm_kusto_database_principal_assignment.ingestion_additional_viewers["grafana"].name == "ing-viewer-grafana" && azurerm_kusto_database_principal_assignment.ingestion_additional_viewers["grafana"].database_name == "Ingestion" && azurerm_kusto_database_principal_assignment.ingestion_additional_viewers["grafana"].role == "Viewer"
    error_message = "Ingestion viewer must be name=ing-viewer-{key}, database=Ingestion, role=Viewer."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_cost_export — cost_management_exports_principal_id set.
# F-3 verification: count=1 path must plan without apply-time errors.
# -----------------------------------------------------------------------
run "happy_with_cost_export" {
  command = plan

  variables {
    cost_management_exports_principal_id = "aaaaaaaa-0000-0000-0000-000000000001"
  }

  assert {
    condition     = length(module.cost_mgmt_exports_storage) == 1
    error_message = "cost_mgmt_exports_storage module must plan 1 instance when principal_id is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_no_cost_export — cost_management_exports_principal_id=null.
# -----------------------------------------------------------------------
run "happy_no_cost_export" {
  command = plan

  variables {
    cost_management_exports_principal_id = null
  }

  assert {
    condition     = length(module.cost_mgmt_exports_storage) == 0
    error_message = "cost_mgmt_exports_storage module must plan 0 instances when principal_id is null."
  }
}

# -----------------------------------------------------------------------
# Test 6: validator_naming_xor_fails — var.name=null + naming vars null.
# Expects XOR validator failure.
# -----------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    name                 = null
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}
