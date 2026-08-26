# Plan-time tests for the AvdImageTemplate module.
#
# Mocks azapi. Covers:
#   1. happy_defaults           — required-only: PlatformImage source, SharedImage distribute, defaults
#   2. happy_powershell_customizer — one PowerShell customizer rendered into customize[]
#   3. happy_source_plan        — source_plan set → source.planInfo present
#   4. happy_target_regions     — explicit multi-region replication
#   5. validator_customizer_xor — script_uri AND inline set → fail
#   6. validator_run_as_system  — run_as_system without run_elevated → fail
#   7. validator_invalid_identity — malformed identity_ids → fail
#   8. validator_invalid_rg     — malformed resource_group_id → fail
#
# Run with:
#   cd modules/AvdImageTemplate
#   terraform init -backend=false
#   terraform test

mock_provider "azapi" {}

variables {
  template_name     = "it-win11-avd-m365-dev"
  location          = "germanywestcentral"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-image"
  identity_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-image/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-aib"
  ]
  image_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-nprd-gwc-shared/providers/Microsoft.Compute/galleries/gal_avd_nprd_gwc/images/win11-avd-m365-dev"
}

# ---------------------------------------------------------------------
# Test 1: happy_defaults
# ---------------------------------------------------------------------
run "happy_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.template.body.properties.buildTimeoutInMinutes == 120
    error_message = "buildTimeoutInMinutes must default to 120."
  }

  assert {
    condition     = azapi_resource.template.body.properties.source.type == "PlatformImage"
    error_message = "source.type must be PlatformImage."
  }

  assert {
    condition     = azapi_resource.template.body.properties.distribute[0].type == "SharedImage"
    error_message = "distribute[0].type must be SharedImage."
  }

  assert {
    condition     = azapi_resource.template.body.properties.distribute[0].runOutputName == "it-win11-avd-m365-dev"
    error_message = "run_output_name must default to template_name."
  }

  assert {
    condition     = azapi_resource.template.body.properties.distribute[0].targetRegions[0].name == "germanywestcentral"
    error_message = "target_regions must default to a single replica in var.location."
  }

  # No purchase plan supplied → no planInfo key.
  assert {
    condition     = !can(azapi_resource.template.body.properties.source.planInfo)
    error_message = "source.planInfo must be absent when source_plan is null."
  }

  # autoRun disabled by default → key absent.
  assert {
    condition     = !can(azapi_resource.template.body.properties.autoRun)
    error_message = "autoRun must be absent when auto_run_enabled is false (default)."
  }
}

# ---------------------------------------------------------------------
# Test 1b: happy_auto_run — auto_run_enabled = true → autoRun.state.
# ---------------------------------------------------------------------
run "happy_auto_run" {
  command = plan

  variables {
    auto_run_enabled = true
  }

  assert {
    condition     = azapi_resource.template.body.properties.autoRun.state == "Enabled"
    error_message = "autoRun.state must be Enabled when auto_run_enabled is true."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_powershell_customizer
# ---------------------------------------------------------------------
run "happy_powershell_customizer" {
  command = plan

  variables {
    customizers = [{
      name         = "InstallVSCodeDev"
      type         = "PowerShell"
      script_uri   = "https://raw.githubusercontent.com/org/repo/main/install-vscode.ps1"
      run_elevated = true
    }]
  }

  assert {
    condition     = length(azapi_resource.template.body.properties.customize) == 1
    error_message = "One customizer must be rendered."
  }

  assert {
    condition     = azapi_resource.template.body.properties.customize[0].type == "PowerShell"
    error_message = "customizer type must be PowerShell."
  }

  assert {
    condition     = azapi_resource.template.body.properties.customize[0].scriptUri == "https://raw.githubusercontent.com/org/repo/main/install-vscode.ps1"
    error_message = "customizer scriptUri must be passed through."
  }

  assert {
    condition     = azapi_resource.template.body.properties.customize[0].runElevated == true
    error_message = "customizer runElevated must be passed through."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_source_plan — planInfo rendered
# ---------------------------------------------------------------------
run "happy_source_plan" {
  command = plan

  variables {
    source_plan = {
      name      = "win11-25h2-avd-m365"
      product   = "office-365"
      publisher = "microsoftwindowsdesktop"
    }
  }

  assert {
    condition     = azapi_resource.template.body.properties.source.planInfo.planName == "win11-25h2-avd-m365"
    error_message = "source.planInfo.planName must match source_plan.name."
  }

  assert {
    condition     = azapi_resource.template.body.properties.source.planInfo.planProduct == "office-365"
    error_message = "source.planInfo.planProduct must match source_plan.product."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_target_regions — explicit multi-region
# ---------------------------------------------------------------------
run "happy_target_regions" {
  command = plan

  variables {
    target_regions = [
      { name = "germanywestcentral" },
      { name = "westeurope", replica_count = 2, storage_account_type = "Premium_LRS" },
    ]
  }

  assert {
    condition     = length(azapi_resource.template.body.properties.distribute[0].targetRegions) == 2
    error_message = "Both target regions must be rendered."
  }

  assert {
    condition     = azapi_resource.template.body.properties.distribute[0].targetRegions[1].storageAccountType == "Premium_LRS"
    error_message = "Second region storageAccountType must be Premium_LRS."
  }
}

# ---------------------------------------------------------------------
# Test 5: validator_customizer_xor — script_uri AND inline → fail
# ---------------------------------------------------------------------
run "validator_customizer_xor" {
  command = plan

  variables {
    customizers = [{
      name       = "Bad"
      script_uri = "https://example/x.ps1"
      inline     = ["Write-Host hi"]
    }]
  }

  expect_failures = [var.customizers]
}

# ---------------------------------------------------------------------
# Test 6: validator_run_as_system — needs run_elevated → fail
# ---------------------------------------------------------------------
run "validator_run_as_system" {
  command = plan

  variables {
    customizers = [{
      name          = "Bad"
      inline        = ["Write-Host hi"]
      run_as_system = true
      run_elevated  = false
    }]
  }

  expect_failures = [var.customizers]
}

# ---------------------------------------------------------------------
# Test 7: validator_invalid_identity — malformed ID → fail
# ---------------------------------------------------------------------
run "validator_invalid_identity" {
  command = plan

  variables {
    identity_ids = ["not-an-identity"]
  }

  expect_failures = [var.identity_ids]
}

# ---------------------------------------------------------------------
# Test 8: validator_invalid_rg — malformed RG ID → fail
# ---------------------------------------------------------------------
run "validator_invalid_rg" {
  command = plan

  variables {
    resource_group_id = "/subscriptions/xxx/rg/wrong"
  }

  expect_failures = [var.resource_group_id]
}
