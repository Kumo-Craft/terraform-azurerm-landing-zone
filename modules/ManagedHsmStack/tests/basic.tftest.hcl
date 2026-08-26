# Plan-time tests for the ManagedHsmStack module.
#
# Mocks azurerm + time. Composes ../ManagedHsm + ../PrivateEndpoint.
# HSM-input validations are covered by the ../ManagedHsm leaf's own tests;
# here we cover composition, naming wiring, and Stack-specific validators.
#
# Covers:
#   1. happy_default    — HSM + PE composed; derived names wired through
#   2. workload_suffix  — optional workload flows into both HSM and PE names
#   3. validator_bad_subnet_id       — malformed subnet id → fail
#   4. validator_bad_pe_ip           — malformed static PE IP → fail
#
# Run with:
#   cd modules/ManagedHsmStack
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs.
variables {
  subscription_acronym = "idt"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-idt-prod-gwc-hsm"
  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-idt-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-idt/subnets/snet-pe"
  admin_object_ids     = ["11111111-1111-1111-1111-111111111111"]
  tenant_id            = "00000000-0000-0000-0000-000000000000"
  private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-idt-prod-gwc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.managedhsm.azure.net"]
}

# -----------------------------------------------------------------------
# Test 1: happy_default — HSM + PE composed with wired names.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  assert {
    condition     = module.hsm.name == "mhsm-idt-prod-gwc"
    error_message = "HSM name must derive as mhsm-{acr}-{env}-{region}."
  }

  assert {
    condition     = length(module.pe.ids) == 1
    error_message = "Exactly one Private Endpoint must be composed."
  }

  assert {
    condition     = output.private_endpoint_name == "pep-mhsm-idt-prod-gwc"
    error_message = "PE name must derive as pep-{hsm_name}."
  }

  assert {
    condition     = module.pe.resources["this"].private_service_connection[0].subresource_names == tolist(["managedhsm"])
    error_message = "PE must target the 'managedhsm' sub-resource (not 'vault')."
  }
}

# -----------------------------------------------------------------------
# Test 2: workload_suffix — optional workload flows into both names.
# -----------------------------------------------------------------------
run "workload_suffix" {
  command = plan

  variables {
    workload = "keys"
  }

  assert {
    condition     = output.hsm_name == "mhsm-idt-prod-gwc-keys"
    error_message = "workload must append to the HSM name."
  }

  assert {
    condition     = output.private_endpoint_name == "pep-mhsm-idt-prod-gwc-keys"
    error_message = "workload must flow through to the PE name."
  }
}

# -----------------------------------------------------------------------
# Test 2b: backup_identity — opt-in UAMI + Storage Blob Data Contributor.
# -----------------------------------------------------------------------
run "backup_identity" {
  command = plan

  variables {
    enable_backup_identity  = true
    backup_storage_scope_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-idt-prod-gwc-bkp/providers/Microsoft.Storage/storageAccounts/stidtprodgwcbkp/blobServices/default/containers/mhsm-backup"
  }

  assert {
    condition     = length(module.backup_identity) == 1
    error_message = "Backup UAMI must be composed when enable_backup_identity = true."
  }

  assert {
    condition     = module.backup_identity[0].name == "id-mhsm-idt-prod-gwc-backup"
    error_message = "Backup UAMI name must default to id-{hsm_name}-backup."
  }

  assert {
    condition     = length(module.backup_identity[0].role_assignment_ids) == 1
    error_message = "Storage Blob Data Contributor role assignment must be created when backup_storage_scope_id is set."
  }
}

# -----------------------------------------------------------------------
# Test 2c: backup_identity_off — disabled by default, no UAMI.
# -----------------------------------------------------------------------
run "backup_identity_off_by_default" {
  command = plan

  assert {
    condition     = length(module.backup_identity) == 0
    error_message = "No backup UAMI must be composed by default."
  }

  assert {
    condition     = output.backup_identity_id == null
    error_message = "backup_identity_id output must be null when disabled."
  }
}

# -----------------------------------------------------------------------
# Test 3: validator_bad_subnet_id — malformed subnet id → fail.
# -----------------------------------------------------------------------
run "validator_bad_subnet_id" {
  command = plan

  variables {
    subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg"
  }

  expect_failures = [var.subnet_id]
}

# -----------------------------------------------------------------------
# Test 4: validator_bad_pe_ip — malformed static PE IP → fail.
# -----------------------------------------------------------------------
run "validator_bad_pe_ip" {
  command = plan

  variables {
    pe_private_ip_address = "not-an-ip"
  }

  expect_failures = [var.pe_private_ip_address]
}
