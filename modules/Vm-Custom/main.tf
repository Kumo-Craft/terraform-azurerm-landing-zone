###############################################################
# MODULE: Vm-Custom - Main
# NIC + Linux VM (SSH-key auth, flexible image source) +
# optional Entra SSH login extension + optional data disks +
# CMK / host encryption + Trusted Launch.
###############################################################

resource "time_static" "time" {} # stable CreatedOn timestamp

###############################################################
# Naming Convention
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
  vm_base_name = var.name != null ? var.name : module.naming["this"].result.virtual_machine.name

  nic_base_name = (
    var.name != null
    ? replace(var.name, "/^vm-/", "nic-")
    : module.naming["this"].result.network_interface.name
  )

  computer_name = (
    var.computer_name_prefix != null
    ? var.computer_name_prefix
    : (
      var.name != null
      ? substr(replace(var.name, "-", ""), 0, 24)
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
  data_disk_instances = {
    for pair in flatten([
      for vm_key, vm in local.vms : [
        for disk_key, disk in var.data_disks : {
          key                  = "${vm_key}-${disk_key}"
          vm_key               = vm_key
          vm_name              = vm.vm_name
          disk_key             = disk_key
          disk_size_gb         = disk.disk_size_gb
          lun                  = disk.lun
          storage_account_type = disk.storage_account_type
          caching              = disk.caching
          create_option        = disk.create_option
          zone                 = vm.zone
        }
      ]
    ]) : pair.key => pair
  }

  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # Password auth is enabled only when a Key Vault secret is supplied.
  password_auth_enabled = var.admin_password_kv_id != null

  created_on_tag = { CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h")) }
}

###############################################################
# DATA: Optional admin password from Key Vault
###############################################################
data "azurerm_key_vault_secret" "admin_password" {
  count = local.password_auth_enabled ? 1 : 0

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
  ip_forwarding_enabled          = false # secure default — NICs do not forward IP traffic

  ip_configuration {
    name                          = "ipc-default"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(var.tags, local.created_on_tag)
}

###############################################################
# RESOURCE: Linux VMs
###############################################################
resource "azurerm_linux_virtual_machine" "this" {
  for_each = local.vms

  name                = each.value.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  zone                = each.value.zone

  computer_name  = each.value.computer_name
  admin_username = var.admin_username

  # SSH key is always configured (best practice). Password auth is
  # disabled unless a Key Vault password secret was supplied.
  disable_password_authentication = !local.password_auth_enabled
  admin_password                  = local.password_auth_enabled ? data.azurerm_key_vault_secret.admin_password[0].value : null

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.this[each.key].id]

  # Trusted Launch (vTPM + Secure Boot) — requires a Gen2 capable image/size.
  secure_boot_enabled = var.enable_trusted_launch
  vtpm_enabled        = var.enable_trusted_launch

  # VM agent required for AutomaticByPlatform patching and the Entra SSH extension.
  provision_vm_agent = true

  encryption_at_host_enabled = var.encryption_at_host_enabled

  license_type = var.license_type

  patch_mode                                             = var.patch_mode
  patch_assessment_mode                                  = var.patch_mode == "AutomaticByPlatform" ? "AutomaticByPlatform" : "ImageDefault"
  bypass_platform_safety_checks_on_user_schedule_enabled = var.patch_mode == "AutomaticByPlatform" ? var.bypass_platform_safety_checks_on_user_schedule : null

  os_disk {
    name                   = "osdisk-${each.value.vm_name}"
    caching                = var.os_disk.caching
    storage_account_type   = var.os_disk.storage_account_type
    disk_size_gb           = var.os_disk.disk_size_gb
    disk_encryption_set_id = var.disk_encryption_set_id
  }

  # Custom / gallery image takes precedence; otherwise marketplace reference.
  source_image_id = var.source_image_id

  dynamic "source_image_reference" {
    for_each = var.source_image_id == null ? [var.image] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  # Marketplace plan — required for paid/3rd-party offers. Null for
  # first-party images and ignored for custom/gallery images.
  dynamic "plan" {
    for_each = var.source_image_id == null && var.image_plan != null ? [var.image_plan] : []
    content {
      name      = plan.value.name
      publisher = plan.value.publisher
      product   = plan.value.product
    }
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

  tags = merge(var.tags, local.created_on_tag)

  lifecycle {
    ignore_changes = [
      admin_password,    # Password rotated out-of-band
      tags["CreatedOn"], # CreatedOn is immutable post-create
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
  zone                   = each.value.zone # align disk zone with VM zone

  # Secure-by-default network access (CKV_AZURE_251). Blocks the disk's
  # data plane (SAS import/export) from the public internet. DenyAll also
  # blocks private-network export. VM attach/boot, backup/restore and
  # resize are unaffected. Set var.disk_network_access_policy = "AllowPrivate"
  # (+ var.disk_access_id) or "AllowAll" only when SAS export/import is required.
  public_network_access_enabled = var.disk_public_network_access_enabled
  network_access_policy         = var.disk_network_access_policy
  disk_access_id                = var.disk_network_access_policy == "AllowPrivate" ? var.disk_access_id : null

  tags = merge(var.tags, local.created_on_tag)
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.data_disk_instances

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this[each.value.vm_key].id
  lun                = each.value.lun
  caching            = each.value.caching
}

###############################################################
# RESOURCE: VM Extension — Entra ID SSH login (AADSSHLoginForLinux)
# Enables Microsoft Entra auth for SSH; pairs with the VM
# Administrator/User Login RBAC roles. Requires the VM's
# SystemAssigned identity (always enabled above).
###############################################################
resource "azurerm_virtual_machine_extension" "entra_ssh_login" {
  for_each = var.entra_ssh_login_enabled ? local.vms : {}

  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this[each.key].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  tags = merge(var.tags, local.created_on_tag)
}

###############################################################
# RESOURCE: Management Lock per VM
###############################################################
module "lock" {
  source   = "../ResourceLock"
  for_each = var.lock != null ? local.vms : {}

  locks = {
    this = {
      scope      = azurerm_linux_virtual_machine.this[each.key].id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-${each.key}" : null
    }
  }
}

###############################################################
# RESOURCE: Role Assignments per VM
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

  scope                            = azurerm_linux_virtual_machine.this[each.value.vm_key].id
  role_definition_id_or_name       = each.value.ra.role_definition_id_or_name
  principal_id                     = each.value.ra.principal_id
  principal_type                   = each.value.ra.principal_type
  condition                        = each.value.ra.condition
  condition_version                = each.value.ra.condition_version
  description                      = each.value.ra.description
  skip_service_principal_aad_check = each.value.ra.skip_service_principal_aad_check
}
