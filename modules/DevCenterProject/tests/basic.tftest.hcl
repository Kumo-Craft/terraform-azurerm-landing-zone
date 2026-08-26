# Plan-time tests for the DevCenterProject module.
#
# Mocks azurerm + time so plan can resolve without credentials.
#
# Run with:
#   cd modules/DevCenterProject
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  location            = "germanywestcentral"
  resource_group_name = "rg-mgm-prod-gwc-devcenter"
  # Canonical Azure casing uses devCenters (camelCase) — validated case-insensitively.
  dev_center_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-devcenter/providers/Microsoft.DevCenter/devCenters/dc-mgm-prod-gwc-devbox"
}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — name + default SystemAssigned identity.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym       = "mgm"
    environment                = "prod"
    region_code                = "gwc"
    workload                   = "teama"
    maximum_dev_boxes_per_user = 2
  }

  assert {
    condition     = output.name == "dcp-mgm-prod-gwc-teama"
    error_message = "Computed name must follow dcp-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_dev_center_project.this.identity[0].type == "SystemAssigned"
    error_message = "Identity must default to SystemAssigned."
  }

  assert {
    condition     = azurerm_dev_center_project.this.maximum_dev_boxes_per_user == 2
    error_message = "maximum_dev_boxes_per_user must pass through."
  }
}

# ---------------------------------------------------------------------
# Test 2: Validator — invalid dev_center_id must fail.
# ---------------------------------------------------------------------
run "invalid_dev_center_id_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "teama"
    dev_center_id        = "not-a-dev-center-id"
  }

  expect_failures = [var.dev_center_id]
}

# ---------------------------------------------------------------------
# Test 3: Validator — UserAssigned without identity_ids must fail.
# ---------------------------------------------------------------------
run "user_assigned_without_ids_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "teama"

    identity = {
      type = "UserAssigned"
    }
  }

  expect_failures = [var.identity]
}

# ---------------------------------------------------------------------
# Test 4: Legacy name override — explicit name passes through.
# ---------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name = "dcp-existing-team"
  }

  assert {
    condition     = output.name == "dcp-existing-team"
    error_message = "Explicit name override must pass through unchanged."
  }
}

# ---------------------------------------------------------------------
# Test 5: Environment types — deployable env type with creator role +
# user role assignment.
# ---------------------------------------------------------------------
run "environment_types" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "teama"

    environment_types = {
      dev = {
        deployment_target_id          = "/subscriptions/11111111-1111-1111-1111-111111111111"
        creator_role_assignment_roles = ["8e3af657-a8ff-443c-a75c-2fe8c4bcb635"] # Owner
        user_role_assignments = {
          "22222222-2222-2222-2222-222222222222" = ["acdd72a7-3385-48ef-bd42-f606fba81ae7"] # Reader
        }
      }
    }
  }

  assert {
    condition     = azurerm_dev_center_project_environment_type.this["dev"].deployment_target_id == "/subscriptions/11111111-1111-1111-1111-111111111111"
    error_message = "deployment_target_id must pass through."
  }

  assert {
    condition     = azurerm_dev_center_project_environment_type.this["dev"].identity[0].type == "SystemAssigned"
    error_message = "Environment type deployment identity must default to SystemAssigned."
  }

  assert {
    condition     = one(azurerm_dev_center_project_environment_type.this["dev"].user_role_assignment).user_id == "22222222-2222-2222-2222-222222222222"
    error_message = "user_role_assignment block must render from the user_role_assignments map."
  }
}

# ---------------------------------------------------------------------
# Test 6: Validator — deployment_target_id must be a subscription ID.
# ---------------------------------------------------------------------
run "invalid_deployment_target_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "teama"

    environment_types = {
      dev = {
        deployment_target_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-x"
      }
    }
  }

  expect_failures = [var.environment_types]
}
