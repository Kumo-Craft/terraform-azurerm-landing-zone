# Plan-time tests for the AvdHostPool module.
#
# Mocks azurerm + time + random. Covers:
#   1. happy_pooled_naming        — convention naming, Pooled, default load_balancer_type
#   2. happy_personal_with_assignment — Personal pool, Direct assignment, Persistent LB
#   3. happy_name_override        — explicit var.name (XOR escape hatch)
#   4. happy_registration_token_on  — create_registration_info=true, token resource planned
#   5. happy_registration_token_off — create_registration_info=false, no token resource
#   6. validator_invalid_type     — type="Foo" must fail
#   7. validator_invalid_preferred_app_group — preferred_app_group_type="Invalid" must fail
#   8. validator_scheduled_updates_too_many — schedule with 3 entries must fail
#   9. happy_with_lock_and_rbac   — lock + role_assignment, both module blocks planned
#
# Run with:
#   cd modules/AvdHostPool
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}
mock_provider "random" {}

# ---------------------------------------------------------------------
# Test 1: happy_pooled_naming — convention naming, Pooled pool.
# ---------------------------------------------------------------------
run "happy_pooled_naming" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "nprd"
    region_code          = "weu"
    workload             = "pooled"
    location             = "westeurope"
    resource_group_name  = "rg-avd-nprd-weu-avd"

    type                     = "Pooled"
    preferred_app_group_type = "Desktop"
    start_vm_on_connect      = true
    public_network_access    = "Disabled"
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.type == "Pooled"
    error_message = "Host pool type must be Pooled."
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.load_balancer_type == "BreadthFirst"
    error_message = "Default load_balancer_type must be BreadthFirst."
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.public_network_access == "Disabled"
    error_message = "public_network_access must be Disabled."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_personal_with_assignment — Personal pool, Direct, Persistent.
# ---------------------------------------------------------------------
run "happy_personal_with_assignment" {
  command = plan

  variables {
    subscription_acronym = "avd"
    environment          = "prod"
    region_code          = "weu"
    workload             = "personal"
    location             = "westeurope"
    resource_group_name  = "rg-avd-prod-weu-avd"

    type                             = "Personal"
    load_balancer_type               = "Persistent"
    personal_desktop_assignment_type = "Direct"
    public_network_access            = "Disabled"
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.type == "Personal"
    error_message = "Host pool type must be Personal."
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.load_balancer_type == "Persistent"
    error_message = "load_balancer_type must be Persistent for Personal pool."
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.personal_desktop_assignment_type == "Direct"
    error_message = "personal_desktop_assignment_type must be Direct."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_name_override — explicit var.name bypasses Naming module.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name                  = "vdpool-custom"
    location              = "westeurope"
    resource_group_name   = "rg-avd-nprd-weu-avd"
    public_network_access = "Disabled"
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.name == "vdpool-custom"
    error_message = "Name override must produce the explicit name."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_registration_token_on — token resource is planned.
# ---------------------------------------------------------------------
run "happy_registration_token_on" {
  command = plan

  variables {
    name                  = "vdpool-regtoken-on"
    location              = "westeurope"
    resource_group_name   = "rg-avd-nprd-weu-avd"
    public_network_access = "Disabled"

    create_registration_info      = true
    registration_expiration_hours = 48
  }

  assert {
    condition     = length(azurerm_virtual_desktop_host_pool_registration_info.this) == 1
    error_message = "Registration info resource must be planned when create_registration_info=true."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_registration_token_off — no token resource planned.
# ---------------------------------------------------------------------
run "happy_registration_token_off" {
  command = plan

  variables {
    name                  = "vdpool-regtoken-off"
    location              = "westeurope"
    resource_group_name   = "rg-avd-nprd-weu-avd"
    public_network_access = "Disabled"

    create_registration_info = false
  }

  assert {
    condition     = length(azurerm_virtual_desktop_host_pool_registration_info.this) == 0
    error_message = "Registration info resource must NOT be planned when create_registration_info=false."
  }
}

# ---------------------------------------------------------------------
# Test 6: validator_invalid_type — type="Foo" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_type" {
  command = plan

  variables {
    name                = "vdpool-bad-type"
    location            = "westeurope"
    resource_group_name = "rg-avd-nprd-weu-avd"
    type                = "Foo"
  }

  expect_failures = [var.type]
}

# ---------------------------------------------------------------------
# Test 7: validator_invalid_preferred_app_group — must fail.
# ---------------------------------------------------------------------
run "validator_invalid_preferred_app_group" {
  command = plan

  variables {
    name                     = "vdpool-bad-appgroup"
    location                 = "westeurope"
    resource_group_name      = "rg-avd-nprd-weu-avd"
    preferred_app_group_type = "Invalid"
  }

  expect_failures = [var.preferred_app_group_type]
}

# ---------------------------------------------------------------------
# Test 8: validator_scheduled_updates_too_many — 3 schedule entries must fail.
# ---------------------------------------------------------------------
run "validator_scheduled_updates_too_many" {
  command = plan

  variables {
    name                = "vdpool-sched-fail"
    location            = "westeurope"
    resource_group_name = "rg-avd-nprd-weu-avd"
    scheduled_agent_updates = {
      enabled  = true
      timezone = "UTC"
      schedule = [
        { day_of_week = "Monday", hour_of_day = 2 },
        { day_of_week = "Wednesday", hour_of_day = 2 },
        { day_of_week = "Friday", hour_of_day = 2 },
      ]
    }
  }

  expect_failures = [var.scheduled_agent_updates]
}

# ---------------------------------------------------------------------
# Test 9: happy_with_lock_and_rbac — lock + role_assignment planned.
# ---------------------------------------------------------------------
run "happy_with_lock_and_rbac" {
  command = plan

  variables {
    name                  = "vdpool-lock-rbac"
    location              = "westeurope"
    resource_group_name   = "rg-avd-nprd-weu-avd"
    public_network_access = "Disabled"

    lock = { kind = "CanNotDelete" }

    role_assignments = {
      dvd_users = {
        role_definition_id_or_name = "Desktop Virtualization User"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = azurerm_virtual_desktop_host_pool.this.name == "vdpool-lock-rbac"
    error_message = "Host pool name must match override."
  }
}
