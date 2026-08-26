# ComputeGallery

Deploys an **Azure Compute Gallery** (Shared Image Gallery) and, optionally, a single **image definition** inside it. The image definition defaults to a **Trusted-Launch-supported** Gen2 Windows image so custom (golden) images built here line up with the Trusted-Launch AVD session hosts produced by [`AvdSessionHost`](../AvdSessionHost/) — pair the two via `source_image_id`.

## Usage

### Standalone (convention naming + image definition)

```hcl
module "compute_gallery" {
  source = "git::https://github.com/Kumo-Craft/Modules.git//modules/ComputeGallery?ref=v0.3.0"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "avd"
  location             = "germanywestcentral"
  resource_group_name  = "rg-avd-nprd-gwc-shared"

  image_definition_name = "win11-avd-m365-dev"
  image_identifier = {
    publisher = "POST"
    offer     = "win11-avd-m365"
    sku       = "dev"
  }

  tags = { Environment = "Non Production" }
}
```

### Explicit name (escape hatch) + gallery only

```hcl
module "compute_gallery" {
  source = "../ComputeGallery"

  gallery_name          = "gal_avd_nprd_gwc"   # no hyphens allowed
  location              = "germanywestcentral"
  resource_group_name   = "rg-avd-nprd-gwc-shared"
  image_definition_name = null                 # gallery only, no image definition
}
```

### Feeding a session host from the image version

```hcl
module "session_host" {
  source = "../AvdSessionHost"
  # ...
  source_image_id = "${module.compute_gallery.image_definition_id}/versions/1.0.3"
}
```

## Naming

Gallery names **disallow hyphens**. The upstream `Azure/naming/azurerm` handles this per-type (prefix `gal`, no separators), exposed via `result.shared_image_gallery.name`.

| Resource | Source |
|---|---|
| Compute Gallery | `../Naming` → `result.shared_image_gallery.name`, or `var.gallery_name` (override) |
| Image definition | `var.image_definition_name` (no convention — semantic name like `win11-avd-m365-dev`) |

XOR escape hatch: set `gallery_name` **or** all four of `subscription_acronym` / `environment` / `region_code` / `workload`.

## Security type (Trusted Launch / Confidential VM)

The `azurerm_shared_image` resource accepts **at most one** of `trusted_launch_supported`, `trusted_launch_enabled`, `confidential_vm_supported`, `confidential_vm_enabled`. This module exposes a single `security_type` enum and maps it to exactly one flag, so a conflicting combination is impossible:

| `security_type` | azurerm flag set | Meaning |
|---|---|---|
| `Standard` | *(none)* | Legacy Gen1/Gen2, no Trusted Launch |
| `TrustedLaunchSupported` *(default)* | `trusted_launch_supported` | Image usable for **both** Trusted Launch and standard Gen2 VMs |
| `TrustedLaunch` | `trusted_launch_enabled` | Image **requires** Trusted Launch |
| `ConfidentialVmSupported` | `confidential_vm_supported` | Confidential VM + standard Gen2 |
| `ConfidentialVm` | `confidential_vm_enabled` | Confidential VM only |

The default (`TrustedLaunchSupported`) means a VM created from this image inherits Trusted Launch (Secure Boot + vTPM) from the definition — matching `AvdSessionHost` with `enable_trusted_launch = true`.

## Key Inputs

| Name | Default | Description |
|---|---|---|
| `gallery_name` | `null` | Explicit gallery name (no hyphens). Null → convention via `../Naming` |
| `workload` | `"avd"` | Workload segment for the convention name |
| `location` / `resource_group_name` | — | Required |
| `gallery_description` | `null` | Optional gallery description |
| `image_definition_name` | `null` | Image definition name. **`null` = gallery only** |
| `image_identifier` | `POST` / `win11-avd-m365` / `dev` | publisher/offer/sku triple (immutable, unique per gallery) |
| `os_type` | `"Windows"` | `Windows` or `Linux` |
| `hyper_v_generation` | `"V2"` | `V1` or `V2` (V2 required for Trusted Launch) |
| `architecture` | `"x64"` | `x64` or `Arm64` |
| `security_type` | `"TrustedLaunchSupported"` | See table above |
| `purchase_plan` | `null` | Marketplace plan for images derived from a paid offer (e.g. M365) |
| `image_description` | `null` | Optional image definition description |
| `tags` | `{}` | Applied to gallery + image definition |

## Outputs

| Name | Description |
|---|---|
| `gallery_id` | Resource ID of the Compute Gallery |
| `gallery_name` | Gallery name |
| `gallery_unique_name` | Globally unique gallery name (cross-tenant / community sharing) |
| `image_definition_id` | Image definition ID, or `null` when none was created |
| `image_definition_name` | Image definition name, or `null` |

## Notes

- **Image versions are out of scope.** This module creates the gallery and the image *definition*; publishing image *versions* (`azurerm_shared_image_version`) is done by your image-build pipeline (e.g. Azure Image Builder / Packer). Reference a version downstream as `${module.compute_gallery.image_definition_id}/versions/<x.y.z>`.
- **`identifier` and most image flags are immutable** — changing publisher/offer/sku, `os_type`, `hyper_v_generation`, `architecture`, or the security type forces a new image definition.
- **`purchase_plan`** is required only when the golden image is captured from a paid/3rd-party marketplace image that carries a plan (accept terms once with `az vm image terms accept`).

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
