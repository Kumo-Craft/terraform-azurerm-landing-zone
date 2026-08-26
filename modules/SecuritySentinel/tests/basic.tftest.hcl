# Plan-time tests for the SecuritySentinel module.
#
# Mocks azurerm so `command = plan` needs no Azure credentials.
#
# Run with:
#   cd modules/SecuritySentinel
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs.
variables {
  subscription_acronym = "sec"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-sec-prod-gwc-sentinel"
}

# -----------------------------------------------------------------------
# Test 1: happy_minimal — defaults. Secure-by-default posture + no daily cap.
# -----------------------------------------------------------------------
run "happy_minimal" {
  command = plan

  # The LAW is now composed from ../LogAnalyticsWorkspace, so its resource is not
  # addressable from here — assert on the module output. The workspace's own
  # security posture (local auth off, public ingestion/query off, ...) is covered
  # by the leaf module's tests.
  assert {
    condition     = module.law.name == "law-sec-prod-gwc-01"
    error_message = "LAW name must follow law-{acr}-{env}-{region}-{workload} (house prefix preserved via the name override)."
  }

  assert {
    condition     = output.law_name == "law-sec-prod-gwc-01"
    error_message = "law_name output must surface the composed workspace name."
  }

  assert {
    condition     = var.daily_quota_gb == -1
    error_message = "daily_quota_gb must default to -1 (no cap on a Sentinel workspace)."
  }

  assert {
    condition     = var.law_local_authentication_disabled == true
    error_message = "Local (workspace-key) auth must be disabled by default."
  }

  assert {
    condition     = var.law_internet_ingestion_enabled == false && var.law_internet_query_enabled == false
    error_message = "Public ingestion/query must be off by default (private via AMPLS)."
  }
}

# -----------------------------------------------------------------------
# Test 2: connectors_off — no data connectors created by default.
# -----------------------------------------------------------------------
run "connectors_off_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_sentinel_data_connector_azure_active_directory.entra) == 0
    error_message = "Entra ID connector must be off by default."
  }

  assert {
    condition     = length(azurerm_sentinel_data_connector_azure_security_center.defender) == 0
    error_message = "Defender for Cloud connector must be off by default."
  }
}

# -----------------------------------------------------------------------
# Test 3: connectors_on — opt-in both connectors.
# -----------------------------------------------------------------------
run "connectors_opt_in" {
  command = plan

  variables {
    connectors = {
      entra_id           = true
      defender_for_cloud = true
    }
    connector_tenant_id       = "00000000-0000-0000-0000-000000000000"
    connector_subscription_id = "00000000-0000-0000-0000-000000000001"
  }

  assert {
    condition     = length(azurerm_sentinel_data_connector_azure_active_directory.entra) == 1
    error_message = "Entra ID connector must be created when connectors.entra_id = true."
  }

  assert {
    condition     = length(azurerm_sentinel_data_connector_azure_security_center.defender) == 1
    error_message = "Defender for Cloud connector must be created when connectors.defender_for_cloud = true."
  }
}
