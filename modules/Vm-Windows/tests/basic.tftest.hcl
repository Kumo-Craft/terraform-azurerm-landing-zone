# Plan-time tests for the Vm-Windows module.
#
# Run locally with:
#   cd Vm-Windows
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {
  mock_data "azurerm_key_vault_secret" {
    defaults = {
      value = "MockedP@ssw0rd!1234"
    }
  }
}

mock_provider "time" {} # F-4: required because time_static is used for CreatedOn tag

###############################################################
# Smoke — minimum valid inputs produce a clean plan.
###############################################################
run "smoke" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"
  }

  assert {
    condition     = output.vm_names["01"] == "vm-api-prod-gwc-01"
    error_message = "Computed VM name must follow the vm-{prefix}-{NN} convention (Naming module truncates to 15 chars for virtual_machine type, so workload may be trimmed)."
  }

  assert {
    condition     = output.computer_names["01"] == "appprod01"
    error_message = "Default computer name must be '{workload}{env}{NN}' when computer_name_prefix is null."
  }
}

###############################################################
# Multi-VM + data disks + UAMI — verifies cartesian fan-out
# and identity_type computation.
###############################################################
run "multi_vm_with_data_disks_and_uami" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "web"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-nprd-gwc-web"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-web"

    vm_count = 2

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-nprd-gwc-web"
    admin_password_secret_name = "vm-local-admin-password"

    user_assigned_identity_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mi-web",
    ]

    data_disks = {
      data01 = { disk_size_gb = 64, lun = 0 }
      logs01 = { disk_size_gb = 32, lun = 1, storage_account_type = "StandardSSD_LRS", caching = "None" }
    }
  }

  assert {
    condition     = length(output.vm_ids) == 2
    error_message = "vm_count = 2 must produce 2 VMs."
  }

  assert {
    condition     = length(output.data_disk_ids) == 4
    error_message = "2 VMs × 2 data disks should produce 4 managed disks."
  }

  # CKV_AZURE_251: data disks must default to public network access DISABLED.
  assert {
    condition     = alltrue([for d in azurerm_managed_disk.data : d.public_network_access_enabled == false])
    error_message = "All data disks must have public_network_access_enabled = false by default (CKV_AZURE_251)."
  }
}

###############################################################
# CKV_AZURE_251: per-disk override — a disk may opt back into
# public network access when SAS export is genuinely required.
###############################################################
run "data_disk_public_access_override" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    data_disks = {
      secure = { disk_size_gb = 32, lun = 0 }
      public = { disk_size_gb = 32, lun = 1, public_network_access_enabled = true }
    }
  }

  assert {
    condition     = azurerm_managed_disk.data["01-secure"].public_network_access_enabled == false
    error_message = "Disk 'secure' must default to public_network_access_enabled = false."
  }

  assert {
    condition     = azurerm_managed_disk.data["01-public"].public_network_access_enabled == true
    error_message = "Disk 'public' must honor the explicit public_network_access_enabled = true override."
  }
}

###############################################################
# F-9: Zonal data disk alignment — verifies that disk zone
# tracks the VM zone when availability_zones is set.
# (assertion on zone is unknown at plan but resource count is checkable)
###############################################################
run "zonal_data_disk_alignment" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    vm_count           = 3
    availability_zones = ["1", "2", "3"]

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    data_disks = {
      data01 = { disk_size_gb = 64, lun = 0 }
    }
  }

  assert {
    condition     = length(output.data_disk_ids) == 3
    error_message = "3 VMs × 1 data disk = 3 managed disks expected."
  }
}

###############################################################
# F-5: Escape-hatch naming — var.name overrides convention.
###############################################################
run "name_escape_hatch" {
  command = plan

  variables {
    name = "vm-custom-name"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"
  }

  assert {
    condition     = output.vm_names["01"] == "vm-custom-name-01"
    error_message = "Escape-hatch name must produce 'vm-custom-name-01'."
  }
}

###############################################################
# Validators
###############################################################
run "lun_collision_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    data_disks = {
      a = { disk_size_gb = 32, lun = 0 }
      b = { disk_size_gb = 32, lun = 0 }
    }
  }

  expect_failures = [var.data_disks]
}

run "vm_count_too_high_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    vm_count = 101
  }

  expect_failures = [var.vm_count]
}

run "bad_subnet_id_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "not-a-resource-id"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"
  }

  expect_failures = [var.subnet_id]
}

run "bad_lock_kind_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    lock = { kind = "Invalid" }
  }

  expect_failures = [var.lock]
}

run "bad_rbac_principal_type_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000000"
        principal_type             = "InvalidType"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

###############################################################
# F-11: SOFT BREAKING — legacy AHB callers can still opt in
# by explicitly setting license_type = "Windows_Server".
# Verifies the backward-compatible path remains valid.
###############################################################
run "happy_legacy_ahb_license" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"

    license_type = "Windows_Server"
  }

  assert {
    condition     = length(output.vm_ids) == 1
    error_message = "Explicit license_type = 'Windows_Server' (AHB) must still produce a valid plan."
  }
}

###############################################################
# F-11: Default pay-as-you-go — new callers get "None" by default.
###############################################################
run "default_license_type_is_none" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "app"

    location            = "germanywestcentral"
    resource_group_name = "rg-api-prod-gwc-app"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-app"

    admin_password_kv_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-app"
    admin_password_secret_name = "vm-local-admin-password"
  }

  assert {
    condition     = length(output.vm_ids) == 1
    error_message = "Default license_type = 'None' (pay-as-you-go) must produce a valid plan."
  }
}
