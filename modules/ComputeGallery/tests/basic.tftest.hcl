# Plan-time tests for the ComputeGallery module.
#
# Mocks azurerm + random (Naming pulls random transitively). Covers:
#   1. happy_convention_naming     — gallery name via ../Naming, image def created
#   2. happy_name_override         — explicit gallery_name (XOR escape hatch), no ../Naming
#   3. happy_gallery_only          — image_definition_name = null → no shared_image
#   4. happy_trusted_launch_default — default security_type maps to trusted_launch_supported
#   5. happy_confidential_vm       — security_type = ConfidentialVm maps to confidential_vm_enabled
#   6. happy_purchase_plan         — purchase_plan set renders a plan block
#   7. validator_gallery_name_hyphen — hyphen in gallery_name must fail
#   8. validator_naming_xor_fails  — gallery_name=null + missing components must fail
#   9. validator_invalid_security_type — bad security_type must fail
#
# Run with:
#   cd modules/ComputeGallery
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "random" {}

variables {
  location            = "germanywestcentral"
  resource_group_name = "rg-avd-nprd-gwc-shared"
}

# ---------------------------------------------------------------------
# Test 1: happy_convention_naming — name via ../Naming, image created.
# ---------------------------------------------------------------------
run "happy_convention_naming" {
  command = plan

  variables {
    subscription_acronym  = "avd"
    environment           = "nprd"
    region_code           = "gwc"
    workload              = "avd"
    image_definition_name = "win11-avd-m365-dev"
  }

  assert {
    condition     = length(module.naming) == 1
    error_message = "Naming module must be instantiated when gallery_name is null."
  }

  assert {
    condition     = length(azurerm_shared_image.this) == 1
    error_message = "One image definition must be created when image_definition_name is set."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_name_override — explicit gallery_name bypasses Naming.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    gallery_name          = "gal_avd_nprd_gwc"
    image_definition_name = "win11-avd-m365-dev"
  }

  assert {
    condition     = azurerm_shared_image_gallery.this.name == "gal_avd_nprd_gwc"
    error_message = "Gallery name must use the explicit gallery_name override."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must not be instantiated when gallery_name is provided."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_gallery_only — no image definition when name is null.
# ---------------------------------------------------------------------
run "happy_gallery_only" {
  command = plan

  variables {
    gallery_name          = "gal_avd_nprd_gwc"
    image_definition_name = null
  }

  assert {
    condition     = length(azurerm_shared_image.this) == 0
    error_message = "No image definition must be created when image_definition_name is null."
  }
}

# ---------------------------------------------------------------------
# Test 4: happy_trusted_launch_default — default maps to *_supported.
# ---------------------------------------------------------------------
run "happy_trusted_launch_default" {
  command = plan

  variables {
    gallery_name          = "gal_avd_nprd_gwc"
    image_definition_name = "win11-avd-m365-dev"
  }

  assert {
    condition     = azurerm_shared_image.this[0].trusted_launch_supported == true
    error_message = "Default security_type must set trusted_launch_supported = true."
  }

  assert {
    condition     = azurerm_shared_image.this[0].trusted_launch_enabled == null && azurerm_shared_image.this[0].confidential_vm_enabled == null
    error_message = "Only trusted_launch_supported must be set by default; the other flags must be null."
  }

  assert {
    condition     = azurerm_shared_image.this[0].hyper_v_generation == "V2"
    error_message = "hyper_v_generation must default to V2."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_confidential_vm — maps to confidential_vm_enabled only.
# ---------------------------------------------------------------------
run "happy_confidential_vm" {
  command = plan

  variables {
    gallery_name          = "gal_cvm_nprd_gwc"
    image_definition_name = "ubuntu-cvm"
    os_type               = "Linux"
    security_type         = "ConfidentialVm"
    image_identifier = {
      publisher = "POST"
      offer     = "ubuntu-cvm"
      sku       = "22_04"
    }
  }

  assert {
    condition     = azurerm_shared_image.this[0].confidential_vm_enabled == true
    error_message = "security_type = ConfidentialVm must set confidential_vm_enabled = true."
  }

  assert {
    condition     = azurerm_shared_image.this[0].trusted_launch_supported == null
    error_message = "trusted_launch_supported must be null when security_type = ConfidentialVm."
  }
}

# ---------------------------------------------------------------------
# Test 6: happy_purchase_plan — plan block rendered when set.
# ---------------------------------------------------------------------
run "happy_purchase_plan" {
  command = plan

  variables {
    gallery_name          = "gal_avd_nprd_gwc"
    image_definition_name = "win11-avd-m365-dev"
    purchase_plan = {
      name      = "win11-25h2-avd-m365"
      publisher = "microsoftwindowsdesktop"
      product   = "office-365"
    }
  }

  assert {
    condition     = azurerm_shared_image.this[0].purchase_plan[0].name == "win11-25h2-avd-m365"
    error_message = "purchase_plan.name must match the input."
  }
}

# ---------------------------------------------------------------------
# Test 7: validator_gallery_name_hyphen — hyphen must fail.
# ---------------------------------------------------------------------
run "validator_gallery_name_hyphen" {
  command = plan

  variables {
    gallery_name = "gal-avd-nprd-gwc"
  }

  expect_failures = [var.gallery_name]
}

# ---------------------------------------------------------------------
# Test 8: validator_naming_xor_fails — null name + missing components.
# ---------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    gallery_name         = null
    subscription_acronym = null
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "avd"
  }

  expect_failures = [var.gallery_name]
}

# ---------------------------------------------------------------------
# Test 9: validator_invalid_security_type — bad value must fail.
# ---------------------------------------------------------------------
run "validator_invalid_security_type" {
  command = plan

  variables {
    gallery_name          = "gal_avd_nprd_gwc"
    image_definition_name = "win11-avd-m365-dev"
    security_type         = "Foo"
  }

  expect_failures = [var.security_type]
}
