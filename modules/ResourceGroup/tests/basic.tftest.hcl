# Plan-time tests for the ResourceGroup module (map-shape).
#
# These tests run via `terraform test` and only exercise validation logic
# + plan resolution — no real Azure resources are created.
#
# Run locally with:
#   cd ResourceGroup
#   terraform init -backend=false
#   terraform test

# ---------------------------------------------------------------------
# Provider mocks — required so plan can resolve azurerm/time without creds.
# ---------------------------------------------------------------------
mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Naming smoke — segments produce the expected conventional name.
# ---------------------------------------------------------------------
run "naming_smoke" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      mgmt = { workload = "management" }
    }
  }

  assert {
    condition     = azurerm_resource_group.this["mgmt"].name == "rg-mgm-nprd-gwc-management"
    error_message = "Computed RG name must follow the rg-{acr}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = output.names["mgmt"] == "rg-mgm-nprd-gwc-management"
    error_message = "output.names must match the resource name."
  }
}

# ---------------------------------------------------------------------
# Test 2: Explicit per-entry name override wins over computed segments.
# ---------------------------------------------------------------------
run "explicit_name_override" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      mgmt = {
        workload = "management"
        name     = "rg-custom-override"
      }
    }
  }

  assert {
    condition     = output.names["mgmt"] == "rg-custom-override"
    error_message = "Explicit name override must take precedence over computed naming segments."
  }
}

# ---------------------------------------------------------------------
# Test 3: Null-workload guard — plan must fail when an entry has
#         workload=null. The resource_groups variable validation
#         (regex on workload) catches this first; the resource-level
#         lifecycle precondition is a defense-in-depth fallback if
#         the validator is ever weakened.
# ---------------------------------------------------------------------
run "null_workload_guard_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      broken = { workload = null }
    }
  }

  expect_failures = [var.resource_groups]
}

# ---------------------------------------------------------------------
# Test 4: Lock kind validator — invalid kind must fail variable validation.
# ---------------------------------------------------------------------
run "lock_invalid_kind_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      mgmt = {
        workload = "management"
        lock     = { kind = "InvalidKind" }
      }
    }
  }

  expect_failures = [var.resource_groups]
}

# ---------------------------------------------------------------------
# Test 5: Role id-or-name dispatch — GUID path sets role_definition_id;
#         plain name sets role_definition_name. Flat map keying is
#         "<rg_key>|<ra_key>".
# ---------------------------------------------------------------------
run "role_definition_id_or_name_dispatch" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      mgmt = {
        workload = "management"
        role_assignments = {
          by_id = {
            role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
            principal_id               = "00000000-0000-0000-0000-000000000001"
          }
          by_name = {
            role_definition_id_or_name = "Contributor"
            principal_id               = "00000000-0000-0000-0000-000000000002"
          }
        }
      }
    }
  }

  # Positive assertions only — under mock_provider, attributes left null in
  # the resource block resolve to "(known after apply)" at plan time.

  assert {
    condition     = module.role_assignments["mgmt|by_id"].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "A full roleDefinitions path must be assigned to role_definition_id."
  }

  assert {
    condition     = module.role_assignments["mgmt|by_name"].role_definition_name == "Contributor"
    error_message = "A plain role name must be assigned to role_definition_name."
  }
}

# ---------------------------------------------------------------------
# Test 6: Multi-RG — two entries in resource_groups produce two distinct
#         resource group plans. Verifies the for_each path end-to-end.
# ---------------------------------------------------------------------
run "happy_multi_rg" {
  command = plan

  variables {
    subscription_acronym = "shc"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      network = { workload = "network" }
      aks     = { workload = "aks" }
    }
  }

  assert {
    condition     = azurerm_resource_group.this["network"].name == "rg-shc-nprd-gwc-network"
    error_message = "First RG name must follow naming convention."
  }

  assert {
    condition     = azurerm_resource_group.this["aks"].name == "rg-shc-nprd-gwc-aks"
    error_message = "Second RG name must follow naming convention."
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 2
    error_message = "Two entries in resource_groups must produce exactly two resource group plans."
  }
}

# ---------------------------------------------------------------------
# Test 7: Per-RG location override — one entry supplies an explicit
#         location that differs from the set-level default, verifying
#         local.effective_locations[k] picks up the per-entry value.
# ---------------------------------------------------------------------
run "happy_per_rg_location_override" {
  command = plan

  variables {
    subscription_acronym = "shc"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      avd_plane = {
        workload    = "avd"
        location    = "westeurope"
        region_code = "weu"
      }
      shared = {
        workload = "shared"
      }
    }
  }

  assert {
    condition     = azurerm_resource_group.this["avd_plane"].location == "westeurope"
    error_message = "Per-entry location override must be reflected in the resource location."
  }

  assert {
    condition     = azurerm_resource_group.this["shared"].location == "germanywestcentral"
    error_message = "Entry without location override must use the set-level location."
  }

  assert {
    condition     = azurerm_resource_group.this["avd_plane"].name == "rg-shc-nprd-weu-avd"
    error_message = "Per-entry region_code override must be reflected in the computed name."
  }
}

# ---------------------------------------------------------------------
# Test 8: Per-RG tag merge — per-entry tags are merged on top of the
#         set-level tags, with per-entry values winning on conflict.
#         Verifies the merge(local.common_tags, each.value.tags) logic.
# ---------------------------------------------------------------------
run "happy_per_rg_tags_merge" {
  command = plan

  variables {
    subscription_acronym = "shc"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    tags = {
      CostCenter  = "cc-001"
      Environment = "NonProd"
    }

    resource_groups = {
      network = {
        workload = "network"
        tags = {
          CostCenter = "cc-network"
          Team       = "infra"
        }
      }
      shared = {
        workload = "shared"
      }
    }
  }

  # Per-entry tag overrides the set-level value.
  assert {
    condition     = azurerm_resource_group.this["network"].tags["CostCenter"] == "cc-network"
    error_message = "Per-entry tag must override the set-level tag on conflict."
  }

  # Per-entry tag that has no set-level counterpart is still present.
  assert {
    condition     = azurerm_resource_group.this["network"].tags["Team"] == "infra"
    error_message = "Per-entry tag with no set-level conflict must be present."
  }

  # Set-level tag propagates to an entry without per-entry tags.
  assert {
    condition     = azurerm_resource_group.this["shared"].tags["CostCenter"] == "cc-001"
    error_message = "Set-level tag must propagate to entries without per-entry tags."
  }
}

# ---------------------------------------------------------------------
# Test 9: Validator rejects bad region_code — the regex validator on
#         var.region_code must reject values that are not 2-5 lowercase
#         letters (e.g. digits or uppercase characters).
# ---------------------------------------------------------------------
run "validator_invalid_region_code" {
  command = plan

  variables {
    subscription_acronym = "shc"
    environment          = "nprd"
    region_code          = "GWC1"
    location             = "germanywestcentral"

    resource_groups = {
      network = { workload = "network" }
    }
  }

  expect_failures = [var.region_code]
}

# ---------------------------------------------------------------------
# Test 10: Lock composition — an entry with lock fires the ResourceLock
#          child module. Verifies the lock{} forwarding path end-to-end.
# ---------------------------------------------------------------------
run "happy_with_lock_composition" {
  command = plan

  variables {
    subscription_acronym = "shc"
    environment          = "nprd"
    region_code          = "gwc"
    location             = "germanywestcentral"

    resource_groups = {
      network = {
        workload = "network"
        lock     = { kind = "CanNotDelete" }
      }
      shared = {
        workload = "shared"
      }
    }
  }

  # The lock module creates exactly one lock resource — the "network" RG.
  # module.lock.resources maps lock key => azurerm_management_lock object.
  assert {
    condition     = length(module.lock.resources) == 1
    error_message = "Exactly one lock resource must be created by the ResourceLock module."
  }

  assert {
    condition     = contains(keys(module.lock.resources), "network")
    error_message = "The lock resource key must match the resource_groups input key."
  }
}
