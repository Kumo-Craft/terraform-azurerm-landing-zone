# AvdImageTemplate

Defines an **Azure Image Builder (AIB) template** — `Microsoft.VirtualMachineImages/imageTemplates`. There is **no native `azurerm` resource** for AIB, so this module is driven via **`azapi`** (API `2024-02-01`).

The default shape matches the AVD golden-image flow:
- **Source** = a marketplace `PlatformImage` (the Win11 25H2 AVD **M365** image by default),
- **Customize** = your PowerShell/Shell script(s),
- **Distribute** = a new **version** into an existing Compute Gallery image definition (pair with [`ComputeGallery`](../ComputeGallery/)),
- **Build network** = Microsoft-managed (no `vmProfile.vnetConfig`).

> **Creating this resource only *defines* the template — it does not build the image.** Trigger the build out-of-band (see [Running a build](#running-a-build)).

## Usage

```hcl
module "avd_image_template" {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/AvdImageTemplate?ref=v0.4.0"

  template_name     = "it-win11-avd-m365-dev"
  location          = "germanywestcentral"
  resource_group_id = "/subscriptions/.../resourceGroups/rg-avd-nprd-gwc-image"

  # UAMI with rights to write image versions into the target gallery
  identity_ids = [module.aib_identity.id]

  # Base image = the M365 AVD image (paid → needs the purchase plan)
  source_image = {
    publisher = "microsoftwindowsdesktop"
    offer     = "office-365"
    sku       = "win11-25h2-avd-m365"
    version   = "latest"
  }
  source_plan = {
    name      = "win11-25h2-avd-m365"
    product   = "office-365"
    publisher = "microsoftwindowsdesktop"
  }

  customizers = [{
    name         = "InstallVSCodeDev"
    type         = "PowerShell"
    script_uri   = "https://raw.githubusercontent.com/org/repo/main/install-vscode.ps1"
    run_elevated = true
  }]

  # Distribute into the ComputeGallery image definition
  image_definition_id = module.compute_gallery.image_definition_id
  target_regions = [
    { name = "germanywestcentral" },
    { name = "westeurope" },
  ]

  tags = { Environment = "Non Production" }
}
```

## The `source_plan` / M365 image

The `office-365` / `win11-*-avd-m365` image is a **paid marketplace image that carries purchase terms**. AIB's `PlatformImage` source needs the matching `planInfo`, or the build fails. Set `source_plan` and accept the terms once per subscription:

```bash
az vm image terms accept \
  --publisher microsoftwindowsdesktop --offer office-365 --plan win11-25h2-avd-m365
```

Leave `source_plan = null` only for first-party images (e.g. `windows-11` / `win11-*-avd`) that need no plan.

## Identity

`imageTemplates` supports only `None` or **`UserAssigned`** (no SystemAssigned). Supply at least one `identity_ids` entry — a User-Assigned Managed Identity that can write image versions into the target gallery (e.g. a custom role with `Microsoft.Compute/galleries/images/versions/write`, or *Contributor* scoped to the gallery RG). AIB also requires this identity to have rights on the staging resource group.

## Distribution regions

`replicationRegions` + `storageAccountType` are **deprecated** (API 2022-07-01+). This module uses **`targetRegions`** instead:

| field | default | notes |
|---|---|---|
| `name` | — | one entry **must** be the gallery's home region |
| `replica_count` | `1` | replicas in that region |
| `storage_account_type` | `Standard_LRS` | `Standard_LRS` / `Standard_ZRS` / `Premium_LRS` |

Empty `target_regions` ⇒ a single replica in `var.location`.

## Key Inputs

| Name | Default | Description |
|---|---|---|
| `template_name` | — | Image template name (1-64: `A-Za-z0-9-_.`) |
| `location` | — | Build/template region (must be a gallery replication region) |
| `resource_group_id` | — | RG resource ID (azapi `parent_id`) |
| `identity_ids` | — | ≥1 User-Assigned MI IDs |
| `image_definition_id` | — | `galleryImageId` — Compute Gallery image **definition** (append `/versions/x.y.z` for explicit versioning) |
| `source_image` | Win11 25H2 AVD M365 | `PlatformImage` base (publisher/offer/sku/version) |
| `source_plan` | `null` | `planInfo` — required for paid images (M365) |
| `customizers` | `[]` | Ordered PowerShell/Shell steps (`script_uri` **or** `inline`) |
| `target_regions` | `[{name = location}]` | Gallery replication targets |
| `build_timeout_minutes` | `120` | 0-960 (0 = 4h default) |
| `vm_size` | `Standard_D4as_v7` | Build VM size (must exist in `location`) |
| `os_disk_size_gb` | `128` | Build OS disk (0 = image default) |
| `staging_resource_group_id` | `null` | Null = MS-managed random staging RG |
| `auto_run_enabled` | `false` | `true` ⇒ `autoRun.state = Enabled`: Azure auto-starts a build on template create/update (server-side, async — non-blocking). See below |
| `exclude_from_latest` | `false` | Don't tag the new version as `latest` |
| `tags` | `{}` | Template tags + distribution `artifactTags` |

## Outputs

| Name | Description |
|---|---|
| `template_id` | Image template resource ID |
| `template_name` | Image template name |
| `run_output_name` | Distribution runOutput name (query post-build for the produced version) |
| `image_definition_id` | Target gallery image definition (echo) |

## Running a build

Creating the template does not run it. Kick off a build (and wait) with the Azure CLI:

```bash
az resource invoke-action \
  --resource-group <rg> \
  --resource-type Microsoft.VirtualMachineImages/imageTemplates \
  -n <template_name> --action Run
```

Then query the result via the `run_output_name`:

```bash
az resource show \
  --ids "<template_id>/runOutputs/<run_output_name>" \
  --api-version 2024-02-01
```

Typically this is wired into a scheduled workflow so the image is rebuilt from `latest` base + scripts on a cadence, producing a fresh gallery version that [`AvdSessionHost`](../AvdSessionHost/) consumes via `source_image_id`. A ready-made workflow template lives at [`.github/templates/avd-image-build.yml`](../../.github/templates/avd-image-build.yml).

### `auto_run_enabled` vs the scheduled pipeline

- **`auto_run_enabled = true`** (native `autoRun`) — Azure starts a build automatically on template **create/update**. Server-side and async, so it does **not** block `terraform apply`. Good for the *first* build or dev loops, but it has **no cadence** and re-triggers on every template change. Prefer this over any in-Terraform "run action" (which would block the apply for the full build).
- **Scheduled workflow** — the mechanism for **cadence**: rebuild from `latest` base (patches + Windows Updates) → new gallery version on a schedule. This is the recommended primary driver; it targets a *deployed* template, so it belongs in the downstream LZ/platform, using [`.github/templates/avd-image-build.yml`](../../.github/templates/avd-image-build.yml) as the template.

## Notes

- **Immutability.** Image templates are largely immutable — most property changes force a resource replace (delete + recreate). Plan changes accordingly.
- **Script hosting.** `script_uri` must be reachable from the MS-managed build VM: a github raw URL, or a SAS URI to a private Azure Storage blob. Pin integrity with `sha256_checksum` where possible.
- **Out of scope.** This module defines the template only; orchestrating the build run and lifecycle (schedule, wait, cleanup) belongs to your pipeline.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |

## Providers

| Name | Version |
|------|---------|
| azapi | ~> 2.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_resource.template](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| identity\_ids | User-assigned managed identity resource IDs granted to the image template. At least one; it must have permission to write image versions into the target gallery. | `list(string)` | n/a | yes |
| image\_definition\_id | galleryImageId — the Compute Gallery image DEFINITION ID (automatic versioning), e.g. .../galleries/<gal>/images/<def>. Append /versions/<x.y.z> for explicit versioning. | `string` | n/a | yes |
| location | Region where the image template (and the MS-managed build) runs. Must be a region the target gallery replicates to. | `string` | n/a | yes |
| resource\_group\_id | Resource ID of the resource group that holds the image template (azapi parent\_id). | `string` | n/a | yes |
| template\_name | Name of the image template. | `string` | n/a | yes |
| auto\_run\_enabled | When true, sets properties.autoRun.state = Enabled so Azure automatically starts a build on template CREATE or UPDATE (server-side, async — does not block the apply). Leave false and drive builds from a scheduled pipeline for cadence (rebuild from `latest`). Note: it re-triggers on every template update. | `bool` | `false` | no |
| build\_timeout\_minutes | Maximum build duration (all customizers + distribution). 0 = service default (4h). | `number` | `120` | no |
| customizers | Ordered list of customization steps. Each provides script\_uri (github/SAS URI) or inline commands. Trusted script hosting: use a SAS URI or a github raw URL reachable from the MS-managed build VM. | <pre>list(object({<br>    name             = string<br>    type             = optional(string, "PowerShell") # PowerShell | Shell<br>    script_uri       = optional(string)<br>    inline           = optional(list(string))<br>    sha256_checksum  = optional(string)<br>    run_elevated     = optional(bool)         # PowerShell only<br>    run_as_system    = optional(bool)         # PowerShell only<br>    valid_exit_codes = optional(list(number)) # PowerShell only<br>  }))</pre> | `[]` | no |
| exclude\_from\_latest | If true, the produced image version is not marked as 'latest' in the gallery definition. | `bool` | `false` | no |
| os\_disk\_size\_gb | OS disk size (GB) of the build VM. 0 = image default. | `number` | `128` | no |
| run\_output\_name | Unique runOutput name to query the distribution result. Null = defaults to template\_name. | `string` | `null` | no |
| source\_image | Base marketplace (PlatformImage) image to build from. Default: the Win11 25H2 AVD M365 multi-session image. | <pre>object({<br>    publisher = string<br>    offer     = string<br>    sku       = string<br>    version   = optional(string, "latest")<br>  })</pre> | <pre>{<br>  "offer": "office-365",<br>  "publisher": "microsoftwindowsdesktop",<br>  "sku": "win11-25h2-avd-m365",<br>  "version": "latest"<br>}</pre> | no |
| source\_plan | Purchase plan (planInfo) for the source image. Required when the marketplace image carries purchase terms (the office-365 M365 AVD image does). Leave null for first-party images with no plan. Accept terms once: `az vm image terms accept`. | <pre>object({<br>    name      = string # planName<br>    product   = string # planProduct<br>    publisher = string # planPublisher<br>  })</pre> | `null` | no |
| staging\_resource\_group\_id | Optional staging resource group ID for the build. Null = AIB creates a randomly-named staging RG (MS-managed). If set, the RG must be empty and in the same region/subscription. | `string` | `null` | no |
| tags | Tags applied to the image template and set as distribution artifactTags. | `map(string)` | `{}` | no |
| target\_regions | Gallery replication targets. One entry MUST be the gallery's home region. Empty = defaults to a single replica in var.location. | <pre>list(object({<br>    name                 = string<br>    replica_count        = optional(number, 1)<br>    storage_account_type = optional(string, "Standard_LRS")<br>  }))</pre> | `[]` | no |
| vm\_size | Size of the ephemeral build VM. Pick a size available in var.location. Empty string = service default (Standard\_D2ds\_v4 for Gen2). | `string` | `"Standard_D4as_v7"` | no |

## Outputs

| Name | Description |
|------|-------------|
| image\_definition\_id | The Compute Gallery image definition the build distributes into (echo of input). |
| run\_output\_name | The distribution runOutput name — query it post-build for the produced image version details. |
| template\_id | Resource ID of the image template. |
| template\_name | Name of the image template. |
<!-- END_TF_DOCS -->
