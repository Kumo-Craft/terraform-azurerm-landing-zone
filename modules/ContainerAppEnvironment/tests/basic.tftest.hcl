# Plan-time tests for the ContainerAppEnvironment module.
#
# Mocks azurerm + time so plan can resolve without credentials.
#
# Run with:
#   cd modules/ContainerAppEnvironment
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  location                   = "germanywestcentral"
  resource_group_name        = "rg-api-prod-gwc-aca"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law-prod"
}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — name + log-analytics destination.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "web"
  }

  assert {
    condition     = output.name == "cae-api-prod-gwc-web"
    error_message = "Computed name must follow cae-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_container_app_environment.this.logs_destination == "log-analytics"
    error_message = "logs_destination must default to log-analytics."
  }
}

# ---------------------------------------------------------------------
# Test 2: Internal + zone-redundant with subnet (VNet integration).
# ---------------------------------------------------------------------
run "internal_with_subnet" {
  command = plan

  variables {
    subscription_acronym           = "api"
    environment                    = "prod"
    region_code                    = "gwc"
    workload                       = "web"
    infrastructure_subnet_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-aca"
    internal_load_balancer_enabled = true
    zone_redundancy_enabled        = true

    workload_profiles = [{
      name                  = "Consumption"
      workload_profile_type = "Consumption"
    }]
  }

  assert {
    condition     = azurerm_container_app_environment.this.internal_load_balancer_enabled == true
    error_message = "internal_load_balancer_enabled must pass through."
  }

  assert {
    condition     = length(azurerm_container_app_environment.this.workload_profile) == 1
    error_message = "workload_profile block must render."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validator — internal LB without subnet must fail.
# ---------------------------------------------------------------------
run "internal_without_subnet_fails" {
  command = plan

  variables {
    subscription_acronym           = "api"
    environment                    = "prod"
    region_code                    = "gwc"
    workload                       = "web"
    internal_load_balancer_enabled = true
  }

  expect_failures = [var.internal_load_balancer_enabled]
}

# ---------------------------------------------------------------------
# Test 4: Validator — log-analytics destination without LAW must fail.
# ---------------------------------------------------------------------
run "log_analytics_without_law_fails" {
  command = plan

  variables {
    subscription_acronym       = "api"
    environment                = "prod"
    region_code                = "gwc"
    workload                   = "web"
    logs_destination           = "log-analytics"
    log_analytics_workspace_id = null
  }

  expect_failures = [var.log_analytics_workspace_id]
}

# ---------------------------------------------------------------------
# Test 5: azure-monitor destination — LAW must be null.
# ---------------------------------------------------------------------
run "azure_monitor_destination" {
  command = plan

  variables {
    subscription_acronym       = "api"
    environment                = "prod"
    region_code                = "gwc"
    workload                   = "web"
    logs_destination           = "azure-monitor"
    log_analytics_workspace_id = null
  }

  assert {
    condition     = azurerm_container_app_environment.this.logs_destination == "azure-monitor"
    error_message = "logs_destination must pass through as azure-monitor."
  }
}
