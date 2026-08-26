# Plan-time tests for the NetworkWatcher module.
#
# Run with:
#   cd modules/NetworkWatcher
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — 4 house vars + RG name + location produce
#         nw-{acr}-{env}-{region}-{workload} via the Naming submodule.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-nprd-gwc-network"
  }

  assert {
    condition     = azurerm_network_watcher.this.name == "nw-mgm-nprd-gwc-platform"
    error_message = "Convention must produce nw-{acr}-{env}-{region}-{workload}."
  }
}

# ---------------------------------------------------------------------
# Test 2: Legacy `name` override path — Naming submodule bypassed
#         (for_each empty), house vars left null.
# ---------------------------------------------------------------------
run "legacy_name_override" {
  command = plan

  variables {
    name                = "nw-legacy-01"
    location            = "germanywestcentral"
    resource_group_name = "rg-legacy"
    # subscription_acronym, environment, region_code, workload all null
  }

  assert {
    condition     = azurerm_network_watcher.this.name == "nw-legacy-01"
    error_message = "Legacy name override must pass through unchanged."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validation — neither `name` nor the 4 house vars set must
#         fail the cross-var validator on `var.name`.
# ---------------------------------------------------------------------
run "no_name_no_house_vars_fails" {
  command = plan

  variables {
    location            = "germanywestcentral"
    resource_group_name = "rg-test"
    # name = null, all house vars = null
  }

  expect_failures = [var.name]
}
