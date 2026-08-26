# ComputeGallery

Deploys an **Azure Compute Gallery** (Shared Image Gallery) and, optionally, a single **image definition** inside it. The image definition defaults to a **Trusted-Launch-supported** Gen2 Windows image so custom (golden) images built here line up with the Trusted-Launch AVD session hosts produced by [`AvdSessionHost`](../AvdSessionHost/) — pair the two via `source_image_id`.

## Usage

### Standalone (convention naming + image definition)

```hcl
module "compute_gallery" {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/ComputeGallery?ref=v0.3.0"

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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_shared_image.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/shared_image) | resource |
| [azurerm_shared_image_gallery.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/shared_image_gallery) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | ############################################################## REQUIRED ############################################################## | `string` | n/a | yes |
| resource\_group\_name | n/a | `string` | n/a | yes |
| architecture | CPU architecture supported by the image. | `string` | `"x64"` | no |
| environment | n/a | `string` | `null` | no |
| gallery\_description | Optional description for the Compute Gallery. | `string` | `null` | no |
| gallery\_name | Explicit Compute Gallery name override (escape hatch). If set, bypasses ../Naming. If null, the name is derived from the convention via ../Naming (result.shared\_image\_gallery.name). Gallery names allow letters, digits, '.', '\_' — NO hyphens. | `string` | `null` | no |
| hyper\_v\_generation | Hyper-V generation. V2 is required for Trusted Launch / Confidential VM and recommended for Win11 + AVD. | `string` | `"V2"` | no |
| image\_definition\_name | Name of the image definition to create in the gallery (e.g. win11-avd-m365-dev). Set to null to create the gallery only (no image definition). | `string` | `null` | no |
| image\_description | Optional description for the image definition. | `string` | `null` | no |
| image\_identifier | The image definition identifier (publisher/offer/sku). This triple must be unique within the gallery and is immutable. | <pre>object({<br>    publisher = string<br>    offer     = string<br>    sku       = string<br>  })</pre> | <pre>{<br>  "offer": "win11-avd-m365",<br>  "publisher": "POST",<br>  "sku": "dev"<br>}</pre> | no |
| os\_type | OS type of the image definition. | `string` | `"Windows"` | no |
| purchase\_plan | Optional marketplace purchase plan for the image definition. Required when the image is derived from a paid/3rd-party marketplace offer that carries a plan (e.g. the office-365 M365 AVD image). Leave null for first-party / custom images. | <pre>object({<br>    name      = string<br>    publisher = optional(string)<br>    product   = optional(string)<br>  })</pre> | `null` | no |
| region\_code | n/a | `string` | `null` | no |
| security\_type | Security type of the image definition. Maps to exactly one azurerm flag:<br>  - "Standard"                -> none (legacy Gen2 / Gen1)<br>  - "TrustedLaunchSupported"  -> trusted\_launch\_supported  (image can be used for BOTH Trusted Launch and standard Gen2 VMs) [default]<br>  - "TrustedLaunch"           -> trusted\_launch\_enabled    (image REQUIRES Trusted Launch)<br>  - "ConfidentialVmSupported" -> confidential\_vm\_supported<br>  - "ConfidentialVm"          -> confidential\_vm\_enabled<br>Default matches AVD session hosts built with Trusted Launch (secure\_boot + vTPM inherited from the definition). | `string` | `"TrustedLaunchSupported"` | no |
| subscription\_acronym | n/a | `string` | `null` | no |
| tags | Tags applied to the gallery and image definition. | `map(string)` | `{}` | no |
| workload | Workload suffix for the gallery name (e.g. avd). | `string` | `"avd"` | no |

## Outputs

| Name | Description |
|------|-------------|
| gallery\_id | Resource ID of the Compute Gallery. |
| gallery\_name | Name of the Compute Gallery. |
| gallery\_unique\_name | The globally unique name of the Compute Gallery (used for cross-tenant / community sharing). |
| image\_definition\_id | Resource ID of the image definition, or null when none was created (image\_definition\_name = null). |
| image\_definition\_name | Name of the image definition, or null when none was created. |
<!-- END_TF_DOCS -->
