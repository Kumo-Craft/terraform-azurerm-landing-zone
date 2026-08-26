###############################################################
# MODULE: AvdImageTemplate - Main
#
# Azure Image Builder (AIB) template via azapi — there is no native
# azurerm resource for Microsoft.VirtualMachineImages/imageTemplates.
#
# Build model here: MS-managed (no vmProfile.vnetConfig). Base image
# is a marketplace PlatformImage, customized by script(s), distributed
# as a new version into an existing Compute Gallery image definition.
#
# NOTE: Creating this resource DEFINES the template; it does not build
# the image. Trigger a build out-of-band (az CLI / azapi action):
#   az resource invoke-action \
#     --resource-group <rg> \
#     --resource-type Microsoft.VirtualMachineImages/imageTemplates \
#     -n <template_name> --action Run
###############################################################

locals {
  run_output_name = coalesce(var.run_output_name, var.template_name)

  # Default to a single replica in the template's own region when the
  # caller doesn't specify target regions.
  target_regions = length(var.target_regions) > 0 ? var.target_regions : [
    { name = var.location, replica_count = 1, storage_account_type = "Standard_LRS" }
  ]

  # source.planInfo only when a purchase plan is supplied.
  source = merge(
    {
      type      = "PlatformImage"
      publisher = var.source_image.publisher
      offer     = var.source_image.offer
      sku       = var.source_image.sku
      version   = var.source_image.version
    },
    var.source_plan == null ? {} : {
      planInfo = {
        planName      = var.source_plan.name
        planProduct   = var.source_plan.product
        planPublisher = var.source_plan.publisher
      }
    }
  )

  # azapi drops null-valued keys from the request body, so per-customizer
  # fields that don't apply (e.g. runElevated on a Shell step) are omitted.
  customize = [
    for c in var.customizers : {
      type           = c.type
      name           = c.name
      scriptUri      = c.script_uri
      inline         = c.inline
      sha256Checksum = c.sha256_checksum
      runElevated    = c.run_elevated
      runAsSystem    = c.run_as_system
      validExitCodes = c.valid_exit_codes
    }
  ]

  distribute = [
    {
      type              = "SharedImage"
      galleryImageId    = var.image_definition_id
      runOutputName     = local.run_output_name
      excludeFromLatest = var.exclude_from_latest
      artifactTags      = var.tags
      targetRegions = [
        for r in local.target_regions : {
          name               = r.name
          replicaCount       = r.replica_count
          storageAccountType = r.storage_account_type
        }
      ]
    }
  ]

  # autoRun added only when enabled → key is absent (not null) otherwise.
  properties = merge(
    {
      buildTimeoutInMinutes = var.build_timeout_minutes
      stagingResourceGroup  = var.staging_resource_group_id # null → MS-managed staging RG

      vmProfile = {
        vmSize       = var.vm_size
        osDiskSizeGB = var.os_disk_size_gb
        # No vnetConfig → Microsoft-managed build network.
      }

      source     = local.source
      customize  = local.customize
      distribute = local.distribute
    },
    var.auto_run_enabled ? { autoRun = { state = "Enabled" } } : {}
  )
}

resource "azapi_resource" "template" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  name      = var.template_name
  location  = var.location
  parent_id = var.resource_group_id
  tags      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  body = {
    properties = local.properties
  }

  response_export_values = ["id", "name"]
}
