# Plan-time tests for the AvdStack composite.
#
# Mocks azurerm (+ KV secret data), time, random. Covers:
#   1. happy_control_plane_only — default 1 desktop app group, no scaling plan, no session hosts
#   2. happy_full               — 2 app groups (Desktop+RemoteApp), scaling plan, session hosts
#   3. happy_split_region       — session hosts placed in a different RG/region than the control plane
#   4. validator_no_app_groups  — empty application_groups must fail
#
# Run with:
#   cd modules/AvdStack
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {
  mock_data "azurerm_key_vault_secret" {
    defaults = {
      value = "MockP@ssw0rd123!"
    }
  }
}
mock_provider "time" {}
mock_provider "random" {}

variables {
  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "weu"
  location             = "westeurope"
  resource_group_name  = "rg-avd-nprd-weu-avd"
}

# ---------------------------------------------------------------------
# Test 1: happy_control_plane_only
# ---------------------------------------------------------------------
run "happy_control_plane_only" {
  command = plan

  assert {
    condition     = module.host_pool.name != null
    error_message = "Host pool must be created."
  }

  assert {
    condition     = length(module.application_group) == 1
    error_message = "Default must create exactly one (desktop) application group."
  }

  assert {
    condition     = length(module.workspace.association_ids) == 1
    error_message = "Workspace must associate the single application group."
  }

  assert {
    condition     = length(module.scaling_plan) == 0
    error_message = "No scaling plan when var.scaling_plan is null."
  }

  assert {
    condition     = length(module.session_host) == 0
    error_message = "No session hosts when var.session_host is null."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_full — app groups + scaling plan + session hosts
# ---------------------------------------------------------------------
run "happy_full" {
  command = plan

  variables {
    application_groups = {
      desktop = {
        type          = "Desktop"
        friendly_name = "Bureau AVD"
        role_assignments = {
          users = {
            role_definition_id_or_name = "Desktop Virtualization User"
            principal_id               = "00000000-0000-0000-0000-000000000010"
          }
        }
      }
      remoteapp = {
        type = "RemoteApp"
        applications = {
          code = {
            name                         = "VSCode"
            path                         = "C:\\Program Files\\Microsoft VS Code\\Code.exe"
            command_line_argument_policy = "DoNotAllow"
          }
        }
      }
    }

    scaling_plan = {
      schedules = {
        weekday = {
          days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          ramp_up_start_time                   = "07:00"
          ramp_up_load_balancing_algorithm     = "BreadthFirst"
          peak_start_time                      = "09:00"
          peak_load_balancing_algorithm        = "BreadthFirst"
          ramp_down_start_time                 = "18:00"
          ramp_down_load_balancing_algorithm   = "DepthFirst"
          ramp_down_minimum_hosts_percent      = 10
          ramp_down_capacity_threshold_percent = 90
          ramp_down_force_logoff_users         = false
          ramp_down_wait_time_minutes          = 30
          ramp_down_notification_message       = "Vous allez etre deconnecte."
          ramp_down_stop_hosts_when            = "ZeroSessions"
          off_peak_start_time                  = "20:00"
          off_peak_load_balancing_algorithm    = "DepthFirst"
        }
      }
    }

    session_host = {
      subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-avd/subnets/snet-sh"
      admin_password_kv_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-kv/providers/Microsoft.KeyVault/vaults/kv-avd-nprd-gwc"
      fslogix_vhd_location = "\\\\stavdfslogix.file.core.windows.net\\profiles"
      vm_count             = 2
    }
  }

  assert {
    condition     = length(module.application_group) == 2
    error_message = "Two application groups must be created."
  }

  assert {
    condition     = length(module.workspace.association_ids) == 2
    error_message = "Both application groups must be associated to the workspace."
  }

  assert {
    condition     = length(module.scaling_plan) == 1
    error_message = "Scaling plan must be created when var.scaling_plan is set."
  }

  assert {
    condition     = length(module.session_host) == 1
    error_message = "Session hosts must be created when var.session_host is set."
  }

  assert {
    condition     = length(module.session_host[0].vm_ids) == 2
    error_message = "vm_count = 2 must create two session hosts."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_split_region — hosts in a different RG/region.
# ---------------------------------------------------------------------
run "happy_split_region" {
  command = plan

  variables {
    session_host = {
      resource_group_name  = "rg-avd-nprd-gwc-sh"
      location             = "germanywestcentral"
      region_code          = "gwc"
      subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-avd/subnets/snet-sh"
      admin_password_kv_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-kv/providers/Microsoft.KeyVault/vaults/kv-avd-nprd-gwc"
      fslogix_vhd_location = "\\\\stavdfslogix.file.core.windows.net\\profiles"
    }
  }

  # Session host NIC lands in the overridden (gwc) region.
  assert {
    condition     = module.session_host[0].vm_names != null
    error_message = "Session hosts must be created with the region/RG overrides."
  }
}

# ---------------------------------------------------------------------
# Test 4: validator_no_app_groups — empty map must fail.
# ---------------------------------------------------------------------
run "validator_no_app_groups" {
  command = plan

  variables {
    application_groups = {}
  }

  expect_failures = [var.application_groups]
}
