###############################################################
# MODULE: Vm-Windows - Main
# NIC + Windows VM (System/UserAssigned identity) + AAD login
# extension + optional data disks + CMK encryption.
###############################################################

resource "time_static" "time" {} # F-4: stable CreatedOn timestamp

###############################################################
# Naming Convention (F-5)
# XOR: var.name != null → escape hatch, ../Naming not instantiated
#      var.name == null → all 4 convention components required
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  # F-5: Canonical VM base name: override or convention (vm- prefix from Naming module)
  vm_base_name = var.name != null ? var.name : module.naming["this"].result.virtual_machine.name

  # F-5: NIC base name mirrors VM base name with "nic-" replacing "vm-" prefix.
  # When escape hatch is active (var.name != null), derive from var.name directly.
  # When convention naming is active, use the network_interface type from Naming.
  nic_base_name = (
    var.name != null
    ? replace(var.name, "/^vm-/", "nic-")
    : module.naming["this"].result.network_interface.name
  )

  # Computer name: use explicit prefix if provided, else derive from convention segments
  # or from the VM base name when escape hatch is active (strip "vm-" prefix, max 12 chars).
  computer_name = (
    var.computer_name_prefix != null
    ? var.computer_name_prefix
    : (
      var.name != null
      ? substr(replace(var.name, "-", ""), 0, 12)
      : "${coalesce(var.workload, "vm")}${coalesce(var.environment, "")}"
    )
  )

  vms = {
    for i in range(var.vm_count) : format("%02d", i + 1) => {
      index         = i
      suffix        = format("%02d", i + 1)
      vm_name       = "${local.vm_base_name}-${format("%02d", i + 1)}"
      computer_name = "${local.computer_name}${format("%02d", i + 1)}"
      nic_name      = "${local.nic_base_name}-${format("%02d", i + 1)}"
      zone          = length(var.availability_zones) > 0 ? element(var.availability_zones, i) : null
    }
  }

  # Cartesian product: one managed disk + attachment per (vm, data_disk) pair.
  # F-9: zone propagated from vm record so Azure accepts zonal placement.
  data_disk_instances = {
    for pair in flatten([
      for vm_key, vm in local.vms : [
        for disk_key, disk in var.data_disks : {
          key                           = "${vm_key}-${disk_key}"
          vm_key                        = vm_key
          vm_name                       = vm.vm_name
          disk_key                      = disk_key
          disk_size_gb                  = disk.disk_size_gb
          lun                           = disk.lun
          storage_account_type          = disk.storage_account_type
          caching                       = disk.caching
          create_option                 = disk.create_option
          public_network_access_enabled = disk.public_network_access_enabled # CKV_AZURE_251
          zone                          = vm.zone                            # F-9: align disk zone with VM zone
        }
      ]
    ]) : pair.key => pair
  }

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # F-4: stable CreatedOn tag — set once at resource creation, ignored on subsequent applies.
  created_on_tag = { CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h")) }
}

###############################################################
# DATA: Admin password from Key Vault
###############################################################
data "azurerm_key_vault_secret" "admin_password" {
  name         = var.admin_password_secret_name
  key_vault_id = var.admin_password_kv_id
}

###############################################################
# RESOURCE: NICs (one per VM)
###############################################################
resource "azurerm_network_interface" "this" {
  for_each = local.vms

  name                           = each.value.nic_name
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = var.accelerated_networking_enabled
  ip_forwarding_enabled          = false # F-3: explicit secure default — NICs do not forward IP traffic by default

  ip_configuration {
    name                          = "ipc-default"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(var.tags, local.created_on_tag) # F-4
}

###############################################################
# RESOURCE: Windows VMs
###############################################################
resource "azurerm_windows_virtual_machine" "this" {
  for_each = local.vms

  name                = each.value.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  zone                = each.value.zone

  computer_name  = each.value.computer_name
  admin_username = var.admin_username
  admin_password = data.azurerm_key_vault_secret.admin_password.value

  network_interface_ids = [azurerm_network_interface.this[each.key].id]

  secure_boot_enabled = var.enable_trusted_launch
  vtpm_enabled        = var.enable_trusted_launch

  # F-12: Explicit provision_vm_agent = true (schema default is true, but making it
  # explicit documents intent: the VM agent is required for patch_mode =
  # "AutomaticByPlatform" and for the AADLoginForWindows extension to function.
  provision_vm_agent = true

  # F-2: Host-level encryption — CAF secure default = true.
  # Azure platform default is false. Setting true on existing VMs requires VM stop/dealloc.
  # Callers with existing non-encrypted VMs should set encryption_at_host_enabled = false
  # during transition, then schedule a maintenance window to flip back to true.
  encryption_at_host_enabled = var.encryption_at_host_enabled

  license_type = var.license_type

  # F-1: patch_assessment_mode must align with patch_mode to avoid Azure rejecting
  # AutomaticByPlatform patch_mode without a matching assessment mode.
  patch_mode                                             = var.patch_mode
  patch_assessment_mode                                  = var.patch_mode == "AutomaticByPlatform" ? "AutomaticByPlatform" : "ImageDefault" # F-1
  bypass_platform_safety_checks_on_user_schedule_enabled = var.patch_mode == "AutomaticByPlatform" ? var.bypass_platform_safety_checks_on_user_schedule : null
  hotpatching_enabled                                    = var.hotpatching_enabled

  os_disk {
    name                   = "osdisk-${each.value.vm_name}"
    caching                = var.os_disk.caching
    storage_account_type   = var.os_disk.storage_account_type
    disk_size_gb           = var.os_disk.disk_size_gb
    disk_encryption_set_id = var.disk_encryption_set_id
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics_enabled ? [1] : []
    content {
      storage_account_uri = var.boot_diagnostics_storage_account_uri
    }
  }

  tags = merge(var.tags, local.created_on_tag) # F-4

  lifecycle {
    ignore_changes = [
      admin_password,    # Password rotated out-of-band via az vm reset
      tags["CreatedOn"], # F-4: CreatedOn is immutable post-create
    ]
  }
}

###############################################################
# RESOURCE: Data disks (one azurerm_managed_disk per (vm, disk))
###############################################################
resource "azurerm_managed_disk" "data" {
  for_each = local.data_disk_instances

  name                   = "disk-${each.value.vm_name}-${each.value.disk_key}"
  location               = var.location
  resource_group_name    = var.resource_group_name
  storage_account_type   = each.value.storage_account_type
  create_option          = each.value.create_option
  disk_size_gb           = each.value.disk_size_gb
  disk_encryption_set_id = var.disk_encryption_set_id
  zone                   = each.value.zone # F-9: align disk zone with VM zone (Azure rejects cross-zone attachments)

  # CKV_AZURE_251: block public network access to the disk's underlying data.
  # Secure-by-default (false); Azure platform default is true. Per-disk override
  # via var.data_disks[*].public_network_access_enabled for SAS export use cases.
  public_network_access_enabled = each.value.public_network_access_enabled

  tags = merge(var.tags, local.created_on_tag) # F-4
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.data_disk_instances

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.this[each.value.vm_key].id
  lun                = each.value.lun
  caching            = each.value.caching
}

###############################################################
# RESOURCE: VM Extension — Entra ID Join (AADLoginForWindows)
# Enables Entra ID auth for RDP/PowerShell; primary access path.
###############################################################
resource "azurerm_virtual_machine_extension" "entra_join" {
  for_each = local.vms

  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.this[each.key].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  tags = merge(var.tags, local.created_on_tag) # F-4
}

###############################################################
# RESOURCE: Management Lock per VM (F-6)
# for_each mirrors the VMs map so each VM gets its own lock.
###############################################################
module "lock" {
  source   = "../ResourceLock"
  for_each = var.lock != null ? local.vms : {}

  locks = {
    this = {
      scope      = azurerm_windows_virtual_machine.this[each.key].id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-${each.key}" : null
    }
  }
}

###############################################################
# RESOURCE: Role Assignments per VM (F-7)
# Composite key: "{role_key}.{vm_key}" — applies every role in
# var.role_assignments to EVERY VM in the pool.
###############################################################
module "rbac" {
  source = "../RoleAssignment"
  for_each = {
    for pair in flatten([
      for role_key, ra in var.role_assignments : [
        for vm_key in keys(local.vms) : {
          key      = "${role_key}.${vm_key}"
          role_key = role_key
          vm_key   = vm_key
          ra       = ra
        }
      ]
    ]) : pair.key => pair
  }

  scope                            = azurerm_windows_virtual_machine.this[each.value.vm_key].id
  role_definition_id_or_name       = each.value.ra.role_definition_id_or_name
  principal_id                     = each.value.ra.principal_id
  principal_type                   = each.value.ra.principal_type
  condition                        = each.value.ra.condition
  condition_version                = each.value.ra.condition_version
  description                      = each.value.ra.description
  skip_service_principal_aad_check = each.value.ra.skip_service_principal_aad_check
}
