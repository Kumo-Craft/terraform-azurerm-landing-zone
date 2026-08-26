###############################################################
# MODULE: ComputeGallery - Main
# Azure Compute Gallery (Shared Image Gallery) + one optional
# image definition. Trusted Launch support is modelled so custom
# images match Trusted-Launch AVD session hosts by default.
###############################################################

###############################################################
# Naming Convention
# XOR: var.gallery_name != null → escape hatch, ../Naming not instantiated
#      var.gallery_name == null → all 4 convention components required
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.gallery_name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  gallery_name = var.gallery_name != null ? var.gallery_name : module.naming["this"].result.shared_image_gallery.name

  # The azurerm_shared_image resource accepts AT MOST ONE security flag.
  # Map the single security_type enum to exactly one non-null flag; the
  # rest stay null (= not specified), satisfying the provider constraint.
  tl_supported  = var.security_type == "TrustedLaunchSupported" ? true : null
  tl_enabled    = var.security_type == "TrustedLaunch" ? true : null
  cvm_supported = var.security_type == "ConfidentialVmSupported" ? true : null
  cvm_enabled   = var.security_type == "ConfidentialVm" ? true : null
}

###############################################################
# RESOURCE: Compute Gallery
###############################################################
resource "azurerm_shared_image_gallery" "this" {
  name                = local.gallery_name
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = var.gallery_description

  tags = var.tags
}

###############################################################
# RESOURCE: Image Definition (optional — null name = gallery only)
###############################################################
resource "azurerm_shared_image" "this" {
  count = var.image_definition_name != null ? 1 : 0

  name                = var.image_definition_name
  gallery_name        = azurerm_shared_image_gallery.this.name
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type            = var.os_type
  hyper_v_generation = var.hyper_v_generation
  architecture       = var.architecture
  description        = var.image_description

  # Exactly one of these is non-null (see locals) — the rest are omitted.
  trusted_launch_supported  = local.tl_supported
  trusted_launch_enabled    = local.tl_enabled
  confidential_vm_supported = local.cvm_supported
  confidential_vm_enabled   = local.cvm_enabled

  identifier {
    publisher = var.image_identifier.publisher
    offer     = var.image_identifier.offer
    sku       = var.image_identifier.sku
  }

  dynamic "purchase_plan" {
    for_each = var.purchase_plan == null ? [] : [var.purchase_plan]
    content {
      name      = purchase_plan.value.name
      publisher = purchase_plan.value.publisher
      product   = purchase_plan.value.product
    }
  }

  tags = var.tags
}
