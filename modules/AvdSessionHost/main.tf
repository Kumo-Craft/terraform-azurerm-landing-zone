###############################################################
# MODULE: AvdSessionHost - Main
# POC-sized: NIC + VM + 3 extensions (Entra join, AVD DSC, FSLogix)
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention (F-12)
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
  # Canonical VM base name: override or convention (vm- prefix from Naming module)
  vm_base_name = var.name != null ? var.name : module.naming["this"].result.virtual_machine.name

  # NIC base name mirrors VM base name with "nic-" replacing "vm-" prefix.
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
      : "avd${var.environment}${var.region_code}"
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

  # FSLogix registry setup + Entra Kerberos (one-shot PowerShell)
  fslogix_command = join(" ; ", [
    "New-Item -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Force | Out-Null",
    "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'Enabled' -Value 1 -Type DWord",
    "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'VHDLocations' -Value '${var.fslogix_vhd_location}' -Type MultiString",
    "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord",
    "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -Type DWord",
    "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\FSLogix\\Profiles' -Name 'SizeInMBs' -Value ${var.fslogix_profile_size_mb} -Type DWord",
    "New-Item -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa\\Kerberos\\Parameters' -Force | Out-Null",
    "Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa\\Kerberos\\Parameters' -Name 'CloudKerberosTicketRetrievalEnabled' -Value 1 -Type DWord",
    "New-Item -Path 'HKLM:\\Software\\Policies\\Microsoft\\AzureADAccount' -Force | Out-Null",
    "Set-ItemProperty -Path 'HKLM:\\Software\\Policies\\Microsoft\\AzureADAccount' -Name 'LoadCredKeyFromProfile' -Value 1 -Type DWord"
  ])

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
# RESOURCE: NICs (one per VM) — F-7: ip_forwarding_enabled = false explicit
###############################################################
resource "azurerm_network_interface" "this" {
  for_each = local.vms

  name                           = each.value.nic_name
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = var.accelerated_networking_enabled
  ip_forwarding_enabled          = false # F-7: explicit secure default

  ip_configuration {
    name                          = "ipc-default"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(var.tags, local.created_on_tag) # F-4
}

###############################################################
# RESOURCE: Windows Session Host VMs
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

  # Trusted Launch (vTPM + Secure Boot) — MS recommended for Win11 + AVD
  secure_boot_enabled = var.enable_trusted_launch
  vtpm_enabled        = var.enable_trusted_launch

  # F-3: VM agent must be present for AutomaticByPlatform + AVD DSC
  provision_vm_agent = true

  # F-2: Host-level encryption — CAF secure default
  encryption_at_host_enabled = var.encryption_at_host_enabled

  # AHB / M365 entitlement — avoids paying full Windows compute price.
  license_type = var.license_type

  # Patch orchestration via Update Manager (modern AVD pattern).
  patch_mode                                             = var.patch_mode
  patch_assessment_mode                                  = var.patch_mode == "AutomaticByPlatform" ? "AutomaticByPlatform" : "ImageDefault" # F-1
  bypass_platform_safety_checks_on_user_schedule_enabled = var.patch_mode == "AutomaticByPlatform" ? var.bypass_platform_safety_checks_on_user_schedule : null
  hotpatching_enabled                                    = var.hotpatching_enabled

  # F-8: Azure-managed boot diagnostics (no cost, no SA required)
  boot_diagnostics {}

  os_disk {
    name = "osdisk-${each.value.vm_name}"
    # Ephemeral OS requires caching=ReadOnly (Azure constraint)
    caching              = var.os_disk.ephemeral ? "ReadOnly" : var.os_disk.caching
    storage_account_type = var.os_disk.storage_account_type
    disk_size_gb         = var.os_disk.disk_size_gb

    dynamic "diff_disk_settings" {
      for_each = var.os_disk.ephemeral ? [1] : []
      content {
        option    = "Local"
        placement = "ResourceDisk"
      }
    }
  }

  # Custom Compute Gallery image (takes precedence over image/image_plan).
  # When set, source_image_reference + plan below are suppressed. The image
  # inherits Trusted Launch from its gallery definition — secure_boot/vtpm above
  # stay driven by var.enable_trusted_launch, no change needed.
  source_image_id = var.source_image_id

  # Marketplace plan — required for paid/3rd-party offers (office-365 M365 image).
  # Null for first-party Microsoft images (windows-11 AVD multi-session).
  # Skipped entirely when a custom gallery image (source_image_id) is used.
  dynamic "plan" {
    for_each = var.source_image_id == null && var.image_plan != null ? [var.image_plan] : []
    content {
      name      = plan.value.name
      publisher = plan.value.publisher
      product   = plan.value.product
    }
  }

  # Marketplace image reference — only when no custom gallery image is supplied.
  dynamic "source_image_reference" {
    for_each = var.source_image_id == null ? [1] : []
    content {
      publisher = var.image.publisher
      offer     = var.image.offer
      sku       = var.image.sku
      version   = var.image.version
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, local.created_on_tag) # F-4

  lifecycle {
    ignore_changes = [
      admin_password, # Password rotated out-of-band via az vm reset command
      tags["CreatedOn"],
    ]

    # Ephemeral OS requires the VM size to have a temp/resource disk large
    # enough for the OS image. The 2-vCPU "s" variants (no 'd') of v3/v4/v5
    # only have ~75 GiB temp, which cannot host a 128 GiB ephemeral OS disk.
    # Use a 'ds' variant (D2ds_v5+) or ≥ 4-vCPU 's' variant (D4s_v5+).
    precondition {
      condition = !try(var.os_disk.ephemeral, true) || !contains(
        [
          "Standard_D2s_v3", "Standard_D2s_v4", "Standard_D2s_v5",
          "Standard_D2as_v4", "Standard_D2as_v5",
          "Standard_B2s", "Standard_B2ms",
        ],
        var.vm_size
      )
      error_message = "Ephemeral OS disk requires a vm_size with sufficient temp storage. The 2-vCPU 's' variants (Standard_D2s_v*, Standard_D2as_v*) have only ~75 GiB temp — use ≥ 4-vCPU (D4s_v5+) or a 'ds' variant (D2ds_v5+ has explicit data disk). Set os_disk.ephemeral = false to use a managed OS disk instead."
    }
  }
}

###############################################################
# RESOURCE: VM Extension — Entra ID Join (AADLoginForWindows)
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
# RESOURCE: VM Extension — AVD DSC (session host registration)
###############################################################
resource "azurerm_virtual_machine_extension" "avd_dsc" {
  for_each = local.vms

  name               = "AVDDscExtension"
  virtual_machine_id = azurerm_windows_virtual_machine.this[each.key].id
  publisher          = "Microsoft.Powershell"
  type               = "DSC"
  # F-16: DSC artifact gallery: https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_<version>.zip
  # type_handler_version "2" + auto_upgrade_minor_version = true handles minor patches automatically.
  # Major version pin should be re-verified on each provider upgrade cycle.
  type_handler_version       = "2.83"
  auto_upgrade_minor_version = true

  # Microsoft's AddSessionHost DSC expects a pscredential-style token.
  # Public side uses PrivateSettingsRef to reference the secret in protected settings.
  settings = jsonencode({
    modulesUrl            = var.avd_dsc_artifact_url
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      hostPoolName = var.hostpool_name
      registrationInfoTokenCredential = {
        UserName = "PLACEHOLDER_DO_NOT_USE"
        Password = "PrivateSettingsRef:RegistrationInfoToken"
      }
      aadJoin = true
    }
  })

  protected_settings = jsonencode({
    Items = {
      RegistrationInfoToken = var.hostpool_registration_token
    }
  })

  depends_on = [azurerm_virtual_machine_extension.entra_join]
  tags       = merge(var.tags, local.created_on_tag) # F-4
}

###############################################################
# RESOURCE: VM Extension — FSLogix Registry (CustomScriptExtension)
###############################################################
resource "azurerm_virtual_machine_extension" "fslogix" {
  for_each = local.vms

  name                       = "FslogixConfig"
  virtual_machine_id         = azurerm_windows_virtual_machine.this[each.key].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -NoProfile -Command \"${local.fslogix_command}\""
  })

  depends_on = [azurerm_virtual_machine_extension.avd_dsc]
  tags       = merge(var.tags, local.created_on_tag) # F-4
}

###############################################################
# RESOURCE: Management Lock per VM (F-5)
# for_each mirrors the VMs map so each session host gets its own lock.
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
# RESOURCE: Role Assignments per VM (F-6)
# Composite key: "{role_key}:{vm_key}" — applies every role in
# var.role_assignments to EVERY session host VM in the pool.
# For external/cross-module scoping, layer ../RoleAssignment directly.
###############################################################
module "rbac" {
  source = "../RoleAssignment"
  for_each = {
    for pair in flatten([
      for role_key, ra in var.role_assignments : [
        for vm_key in keys(local.vms) : {
          key      = "${role_key}:${vm_key}"
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
