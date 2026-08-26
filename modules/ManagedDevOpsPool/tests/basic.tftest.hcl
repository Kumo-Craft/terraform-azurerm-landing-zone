# Plan-time tests for the ManagedDevOpsPool module.
#
# Mocks azurerm + time so plan can resolve without credentials.
#
# Run with:
#   cd modules/ManagedDevOpsPool
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  location              = "germanywestcentral"
  resource_group_name   = "rg-mgm-nprd-gwc-devops"
  dev_center_project_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-nprd-gwc-devops/providers/Microsoft.DevCenter/projects/dcp-mgm-nprd-gwc-devops"
  organizations = [{
    url = "https://dev.azure.com/contoso"
  }]
}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — name, default stateless + isolated network.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"
    maximum_concurrency  = 5
  }

  assert {
    condition     = output.name == "mdp-mgm-nprd-gwc-devops"
    error_message = "Computed name must follow mdp-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = length(azurerm_managed_devops_pool.this.stateless_agent) == 1
    error_message = "Default agent_type must render a stateless_agent block."
  }

  assert {
    condition     = azurerm_managed_devops_pool.this.virtual_machine_scale_set_fabric[0].subnet_id == null
    error_message = "subnet_id must be null by default (isolated Microsoft-managed network)."
  }

  assert {
    condition     = azurerm_managed_devops_pool.this.azure_devops_organization[0].organization[0].parallelism == 5
    error_message = "Unset organization parallelism must default to maximum_concurrency."
  }
}

# ---------------------------------------------------------------------
# Test 2: VNet injection — subnet_id passed to the fabric.
# ---------------------------------------------------------------------
run "vnet_injection" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"

    subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-agents"
  }

  assert {
    condition     = azurerm_managed_devops_pool.this.virtual_machine_scale_set_fabric[0].subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-agents"
    error_message = "subnet_id must be injected into the VM scale set fabric."
  }
}

# ---------------------------------------------------------------------
# Test 3: Stateful agent profile.
# ---------------------------------------------------------------------
run "stateful_agent" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"

    agent_type                      = "stateful"
    stateful_maximum_agent_lifetime = "7.00:00:00"
  }

  assert {
    condition     = length(azurerm_managed_devops_pool.this.stateful_agent) == 1
    error_message = "agent_type = stateful must render a stateful_agent block."
  }

  assert {
    condition     = length(azurerm_managed_devops_pool.this.stateless_agent) == 0
    error_message = "No stateless_agent block when agent_type = stateful."
  }
}

# ---------------------------------------------------------------------
# Test 3b: Manual standby — manual_standby_agent_count primes over automatic.
# ---------------------------------------------------------------------
run "manual_standby_primes" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"

    maximum_concurrency        = 5
    manual_standby_agent_count = 2
    manual_time_zone           = "Romance Standard Time"
  }

  assert {
    condition     = length(azurerm_managed_devops_pool.this.stateless_agent[0].manual_resource_prediction) == 1
    error_message = "manual_resource_prediction must be rendered when manual_standby_agent_count is set."
  }

  assert {
    condition     = azurerm_managed_devops_pool.this.stateless_agent[0].manual_resource_prediction[0].all_week_schedule == 2
    error_message = "all_week_schedule must equal manual_standby_agent_count."
  }

  assert {
    condition     = azurerm_managed_devops_pool.this.stateless_agent[0].manual_resource_prediction[0].time_zone_name == "Romance Standard Time"
    error_message = "time_zone_name must equal manual_time_zone."
  }

  assert {
    condition     = length(azurerm_managed_devops_pool.this.stateless_agent[0].automatic_resource_prediction) == 0
    error_message = "automatic_resource_prediction must NOT be rendered when manual standby is set (exactly one block allowed)."
  }
}

# ---------------------------------------------------------------------
# Test 3c: Validator — manual_standby_agent_count > maximum_concurrency fails.
# ---------------------------------------------------------------------
run "manual_standby_exceeds_max_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"

    maximum_concurrency        = 2
    manual_standby_agent_count = 5
  }

  expect_failures = [var.manual_standby_agent_count]
}

# ---------------------------------------------------------------------
# Test 4: Validator — image with both well_known_image_name and id fails.
# ---------------------------------------------------------------------
run "invalid_image_both_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"

    images = [{
      well_known_image_name = "ubuntu-22.04/latest"
      id                    = "/subscriptions/.../images/custom"
    }]
  }

  expect_failures = [var.images]
}

# ---------------------------------------------------------------------
# Test 5: Validator — invalid dev_center_project_id fails.
# ---------------------------------------------------------------------
run "invalid_project_id_fails" {
  command = plan

  variables {
    subscription_acronym  = "mgm"
    environment           = "nprd"
    region_code           = "gwc"
    workload              = "devops"
    dev_center_project_id = "not-a-project-id"
  }

  expect_failures = [var.dev_center_project_id]
}

# ---------------------------------------------------------------------
# Test 6: Validator — SpecificAccounts permission without accounts fails.
# ---------------------------------------------------------------------
run "specific_accounts_without_accounts_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "devops"

    permission = {
      kind = "SpecificAccounts"
    }
  }

  expect_failures = [var.permission]
}
