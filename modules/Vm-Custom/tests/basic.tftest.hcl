# Plan-time tests for the Vm-Custom (Linux) module.
#
# Mocks azurerm + time so plan can resolve without credentials.
# Covers: convention naming, default marketplace image + SSH-only
# auth, source_image_id precedence, marketplace plan, optional
# password auth via Key Vault, and the validators.
#
# Run with:
#   cd modules/Vm-Custom
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

variables {
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-app"
  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-app"
  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKa0zon4/tSD0KafDi4MTS+I1FuY9EaSNesfop0MLCvL test@vm-custom"
}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — default Ubuntu image, SSH-only auth.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    vm_count             = 1
  }

  # The Naming submodule caps the virtual_machine type at 15 chars (NetBIOS
  # heritage), so for long prefixes the workload segment may be truncated.
  # Assert the module's own contribution: the vm- prefix and the -01 index.
  assert {
    condition     = startswith(azurerm_linux_virtual_machine.this["01"].name, "vm-") && endswith(azurerm_linux_virtual_machine.this["01"].name, "-01")
    error_message = "VM name must start with vm- and end with the -01 index suffix."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["01"].disable_password_authentication == true
    error_message = "Password authentication must be disabled when no Key Vault password is supplied (SSH-only)."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["01"].source_image_reference[0].publisher == "Canonical"
    error_message = "Default marketplace image must be the Canonical Ubuntu reference."
  }

  assert {
    condition     = azurerm_network_interface.this["01"].ip_forwarding_enabled == false
    error_message = "NIC ip_forwarding_enabled must be false."
  }
}

# ---------------------------------------------------------------------
# Test 2: source_image_id precedence — no marketplace reference block.
# ---------------------------------------------------------------------
run "source_image_id_precedence" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    vm_count             = 1
    source_image_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-img/providers/Microsoft.Compute/galleries/cg1/images/hardened-ubuntu/versions/1.0.0"
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.this["01"].source_image_reference) == 0
    error_message = "When source_image_id is set, no source_image_reference block must be rendered."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["01"].source_image_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-img/providers/Microsoft.Compute/galleries/cg1/images/hardened-ubuntu/versions/1.0.0"
    error_message = "source_image_id must be passed through to the VM."
  }
}

# ---------------------------------------------------------------------
# Test 3: Marketplace plan — image_plan renders a plan block.
# ---------------------------------------------------------------------
run "marketplace_plan" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    vm_count             = 1

    image = {
      publisher = "example-publisher"
      offer     = "example-offer"
      sku       = "example-sku"
      version   = "latest"
    }
    image_plan = {
      name      = "example-sku"
      publisher = "example-publisher"
      product   = "example-offer"
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["01"].plan[0].name == "example-sku"
    error_message = "image_plan must render a plan block on the VM."
  }
}

# ---------------------------------------------------------------------
# Test 4: Password auth via Key Vault — disables SSH-only mode.
# ---------------------------------------------------------------------
run "password_auth_via_kv" {
  command = plan

  variables {
    subscription_acronym       = "api"
    environment                = "prod"
    region_code                = "gwc"
    workload                   = "app"
    vm_count                   = 1
    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-kv/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc"
    admin_password_secret_name = "vm-app-admin"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["01"].disable_password_authentication == false
    error_message = "Password authentication must be enabled when a Key Vault password secret is supplied."
  }
}

# ---------------------------------------------------------------------
# Test 5: Data disk secure-by-default network access (CKV_AZURE_251).
# ---------------------------------------------------------------------
run "data_disk_secure_network_defaults" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    vm_count             = 1

    data_disks = {
      data01 = {
        disk_size_gb = 128
        lun          = 0
      }
    }
  }

  assert {
    condition     = azurerm_managed_disk.data["01-data01"].public_network_access_enabled == false
    error_message = "Data disk public_network_access_enabled must default to false (CKV_AZURE_251)."
  }

  assert {
    condition     = azurerm_managed_disk.data["01-data01"].network_access_policy == "DenyAll"
    error_message = "Data disk network_access_policy must default to DenyAll."
  }

  assert {
    condition     = azurerm_managed_disk.data["01-data01"].disk_access_id == null
    error_message = "disk_access_id must be null unless network policy is AllowPrivate."
  }
}

# ---------------------------------------------------------------------
# Test 5b: AllowPrivate without disk_access_id must fail the validator.
# ---------------------------------------------------------------------
run "allow_private_without_disk_access_fails" {
  command = plan

  variables {
    subscription_acronym       = "api"
    environment                = "prod"
    region_code                = "gwc"
    workload                   = "app"
    disk_network_access_policy = "AllowPrivate"
  }

  expect_failures = [var.disk_access_id]
}

# ---------------------------------------------------------------------
# Test 6: Validator — malformed SSH public key must fail.
# ---------------------------------------------------------------------
run "invalid_ssh_key_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    admin_ssh_public_key = "not-an-ssh-key"
  }

  expect_failures = [var.admin_ssh_public_key]
}

# ---------------------------------------------------------------------
# Test 7: Validator — Key Vault id without secret name must fail.
# ---------------------------------------------------------------------
run "kv_id_without_secret_name_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    admin_password_kv_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-kv/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc"
  }

  expect_failures = [var.admin_password_secret_name]
}

# ---------------------------------------------------------------------
# Test 8: Validator — naming XOR (no name, no components) must fail.
# ---------------------------------------------------------------------
run "naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"
    vm_count             = 1
  }

  expect_failures = [var.name]
}
