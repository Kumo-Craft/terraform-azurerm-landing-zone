# Plan-time tests for the DevCenter module.
#
# Mocks azurerm + time so plan can resolve without credentials.
#
# Run with:
#   cd modules/DevCenter
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — name + default SystemAssigned identity.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "devbox"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-prod-gwc-devcenter"
  }

  assert {
    condition     = output.name == "dc-mgm-prod-gwc-devbox"
    error_message = "Computed name must follow dc-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_dev_center.this.identity[0].type == "SystemAssigned"
    error_message = "Identity must default to SystemAssigned."
  }
}

# ---------------------------------------------------------------------
# Test 2: UserAssigned identity passthrough.
# ---------------------------------------------------------------------
run "user_assigned_identity" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "devbox"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-prod-gwc-devcenter"

    identity = {
      type         = "UserAssigned"
      identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-devcenter"]
    }
  }

  assert {
    condition     = azurerm_dev_center.this.identity[0].type == "UserAssigned"
    error_message = "Identity type must pass through as UserAssigned."
  }
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
    workload             = "devbox"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-prod-gwc-devcenter"

    identity = {
      type = "UserAssigned"
    }
  }

  expect_failures = [var.identity]
}

# ---------------------------------------------------------------------
# Test 4: Validator — explicit name too long must fail.
# ---------------------------------------------------------------------
run "name_too_long_fails" {
  command = plan

  variables {
    name                = "dc-this-name-is-definitely-far-too-long-for-a-dev-center"
    location            = "germanywestcentral"
    resource_group_name = "rg-mgm-prod-gwc-devcenter"
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 5: Legacy name override — explicit name passes through.
# ---------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name                = "dc-existing-01"
    location            = "germanywestcentral"
    resource_group_name = "rg-mgm-prod-gwc-devcenter"
  }

  assert {
    condition     = output.name == "dc-existing-01"
    error_message = "Explicit name override must pass through unchanged."
  }
}

# ---------------------------------------------------------------------
# Test 6: Environment types — one resource per name.
# ---------------------------------------------------------------------
run "environment_types" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "devbox"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-prod-gwc-devcenter"

    environment_types = ["sandbox", "dev", "prod"]
  }

  assert {
    condition     = length(azurerm_dev_center_environment_type.this) == 3
    error_message = "One environment type resource must be created per name."
  }

  assert {
    condition     = azurerm_dev_center_environment_type.this["dev"].name == "dev"
    error_message = "Environment type name must match the list entry."
  }
}

# ---------------------------------------------------------------------
# Test 7: Validator — duplicate environment type names must fail.
# ---------------------------------------------------------------------
run "duplicate_environment_types_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "devbox"
    location             = "germanywestcentral"
    resource_group_name  = "rg-mgm-prod-gwc-devcenter"

    environment_types = ["dev", "dev"]
  }

  expect_failures = [var.environment_types]
}
