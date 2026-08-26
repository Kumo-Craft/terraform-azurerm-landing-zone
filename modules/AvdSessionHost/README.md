# AvdSessionHost

Deploys one or more **Windows session host VMs** for an AVD host pool. Each VM gets a NIC, system-assigned identity, optional Trusted Launch, and three extensions (Entra Join → AVD DSC → FSLogix registry config). Admin password is read from Key Vault.

## Usage

### Standalone

```hcl
module "avd_sh" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AvdSessionHost?ref=v0.2.32"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "sh"
  location             = "germanywestcentral"
  resource_group_name  = "rg-avd-nprd-gwc-sh"

  vm_count             = 2
  vm_size              = "Standard_D4s_v5"
  availability_zones   = ["1", "2", "3"]
  subnet_id            = "/subscriptions/.../subnets/snet-avd-nprd-gwc-sh"

  # Win11 24H2 multi-session — AHB activated via license_type
  license_type          = "Windows_Client"
  patch_mode            = "AutomaticByPlatform"
  enable_trusted_launch = true

  # Local admin password from Key Vault
  admin_password_kv_id        = "/subscriptions/.../vaults/kv-avd-nprd-gwc-001"
  admin_password_secret_name  = "sh-local-admin-password"

  # AVD enrollment
  hostpool_name               = "vdpool-avd-nprd-weu-pooled"
  hostpool_registration_token = "<token from AvdHostPool>"

  # FSLogix profile share
  fslogix_vhd_location    = "\\\\stavdfslogix.file.core.windows.net\\profiles"
  fslogix_profile_size_mb = 30000

  # Optional: resource lock + RBAC on every VM
  lock = { kind = "CanNotDelete" }
  role_assignments = {
    vm_user_login = {
      role_definition_id_or_name = "Virtual Machine User Login"
      principal_id               = "<aad-group-object-id>"
      principal_type             = "Group"
    }
  }

  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AvdSessionHost"
}

dependency "host_pool" { config_path = "../hp-avd" }
dependency "rg_sh"     { config_path = "../rg-sh" }
dependency "subnet"    { config_path = "../subnet-avd" }
dependency "kv"        { config_path = "../kv-avd" }
dependency "st_fslogix" { config_path = "../st-avd-fslogix" }

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  location             = include.root.inputs.location
  workload             = "sh"

  vm_count            = 2
  resource_group_name = dependency.rg_sh.outputs.name
  subnet_id           = dependency.subnet.outputs.subnet_ids["snet-avd-nprd-gwc-sh"]

  admin_password_kv_id = dependency.kv.outputs.id

  hostpool_name               = dependency.host_pool.outputs.name
  hostpool_registration_token = dependency.host_pool.outputs.registration_token

  fslogix_vhd_location = "\\\\${dependency.st_fslogix.outputs.name}.file.core.windows.net\\profiles"

  tags = include.root.inputs.common_tags
}
```

## Naming Convention

As of v0.2.32 VM names are produced by the `../Naming` submodule (convention: `vm-{acr}-{env}-{region}-{workload}-{NN}`).
An indexed suffix (`-01`, `-02`, …) is appended automatically for each session host in the pool.

| Resource | Pattern |
|---|---|
| Azure VM | `vm-{subscription_acronym}-{environment}-{region_code}-{workload}-{NN}` |
| Computer name (NetBIOS, max 15 chars) | `{computer_name_prefix}{NN}` (default `avd{environment}{region_code}`) |
| NIC | `nic-{acr}-{env}-{region}-{workload}-{NN}` |

## Breaking Changes (v0.2.32)

### VM naming slug change (F-12)

Previous versions constructed the VM name inline as:
`vm-{subscription_acronym}-{environment}-{region_code}-{workload}-{NN}`

v0.2.32 delegates to `../Naming`, which produces the same pattern via the upstream
`Azure/naming/azurerm` module (`virtual_machine` type prefix is `vm-`).
In most environments the output name is **identical** and no destroy+recreate is required.

If Terraform detects a rename on an existing VM (e.g. the upstream module casing or separator
rules differ from your previous inline name), pin the explicit base name before upgrading:

```hcl
name = "vm-avd-nprd-gwc-sh" # exact pre-upgrade name without the -NN suffix
```

This activates the escape hatch (`var.name != null` → `../Naming` is not instantiated).

### `encryption_at_host_enabled` default flipped to `true` (F-2)

The default was implicitly `false` (provider default) in prior versions. It is now `true`
(CAF secure baseline). Flipping from `false` to `true` on an **existing** VM is an Azure
immutable operation — it requires destroy+recreate. Before upgrading existing session hosts,
either:

- Accept the destroy+recreate (schedule a maintenance window), OR
- Pin `encryption_at_host_enabled = false` in your calling module to preserve existing behavior.

Additionally, the `EncryptionAtHost` feature must be registered in your subscription:
`az feature register --namespace Microsoft.Compute --name EncryptionAtHost`

## Required Inputs

| Name | Description |
|---|---|
| `location` | Azure region |
| `resource_group_name` | Resource group |
| `subnet_id` | Session host subnet |
| `admin_password_kv_id` | Key Vault holding the local admin password |
| `hostpool_name` | AVD host pool name to register with |
| `hostpool_registration_token` | Token from `AvdHostPool` (sensitive) |
| `fslogix_vhd_location` | SMB UNC path to the FSLogix profile share |

At least one of `var.name` (explicit override) or all four of `subscription_acronym` /
`environment` / `region_code` / `workload` must be provided.

## Key Optional Inputs

| Name | Default | Description |
|---|---|---|
| `name` | `null` | Explicit VM base name override — bypasses `../Naming` |
| `vm_count` | `1` | Number of session host VMs |
| `vm_size` | `Standard_D4s_v5` | Min 4 vCPU recommended for Win11 multi-session |
| `image` | Win11 24H2 AVD multi-session | Marketplace image. Ignored when `source_image_id` is set |
| `image_plan` | `null` | Marketplace plan block — **required** for paid/3rd-party offers (e.g. the M365 image). Leave `null` for first-party `windows-11` images. Ignored when `source_image_id` is set |
| `source_image_id` | `null` | Compute Gallery image / image-version ID (or Community/Shared Gallery ID). **Takes precedence** over `image`/`image_plan` — the `source_image_reference` and `plan` blocks are suppressed |
| `os_disk.ephemeral` | `true` | D4s_v5 has 150 GiB temp — fits 128 GiB ephemeral OS |
| `accelerated_networking_enabled` | `true` | SR-IOV. Disable only for VM sizes that don't support it |
| `availability_zones` | `["1","2","3"]` | Round-robin VM placement |
| `enable_trusted_launch` | `true` | vTPM + Secure Boot |
| `encryption_at_host_enabled` | `true` | Host-level encryption (CAF baseline). Requires `EncryptionAtHost` feature registration. Immutable post-create |
| `license_type` | `"Windows_Client"` | AHB / M365 entitlement (avoids paying full Windows compute price) |
| `patch_mode` | `"AutomaticByPlatform"` | Pairs with Azure Update Manager |
| `bypass_platform_safety_checks_on_user_schedule` | `true` | Honor a maintenance configuration |
| `hotpatching_enabled` | `false` | Win11 24H2+ multi-session, opt-in |
| `lock` | `null` | `{kind = "CanNotDelete"/"ReadOnly"}` — applied to every session host VM |
| `role_assignments` | `{}` | Map of RBAC grants applied to every session host VM |

## Ephemeral OS x VM size

`os_disk.ephemeral = true` (default) requires the chosen `vm_size` to expose
a temp/resource disk large enough for the OS image (128 GiB by default). The
2-vCPU "s" variants of v3/v4/v5 only have ~75 GiB of temp storage, which
**cannot** host the ephemeral OS — `terraform plan` will block via a
precondition listing the affected sizes.

## Marketplace plan (M365 image)

The default first-party image (`windows-11` / `win11-24h2-avd`) needs **no** plan.
Paid/3rd-party offers — notably the M365 image (Teams/OneDrive pre-installed) —
carry a mandatory marketplace plan; without a `plan` block the VM apply fails with
*"the image requires a plan"*. Set both `image` and `image_plan`:

```hcl
image = {
  publisher = "microsoftwindowsdesktop"
  offer     = "office-365"
  sku       = "win11-25h2-avd-m365"
  version   = "latest"
}
image_plan = {
  publisher = "microsoftwindowsdesktop"
  product   = "office-365"
  name      = "win11-25h2-avd-m365"
}
```

The plan's purchase terms must be accepted **once per subscription** (out-of-band, non-IaC):

```bash
az vm image terms accept \
  --publisher microsoftwindowsdesktop \
  --offer office-365 \
  --plan win11-25h2-avd-m365
```

| Choose | When |
| --- | --- |
| `Standard_D4s_v5` (or larger 's') | Default for AVD multi-session |
| `Standard_D2ds_v5` / any 'ds' variant | Need 2 vCPUs but want ephemeral OS |
| `os_disk.ephemeral = false` | Need a 2-vCPU 's' variant; pay for managed OS disk |

## Custom Compute Gallery image

To deploy from a custom (golden) image instead of a marketplace SKU, set
`source_image_id` to an Azure Compute Gallery **image** or **image-version** ID.
When set, it takes precedence over `image`/`image_plan`: the `source_image_reference`
and `plan` blocks are suppressed entirely.

```hcl
# Pin an explicit version …
source_image_id = "/subscriptions/.../resourceGroups/rg-avd-shared/providers/Microsoft.Compute/galleries/gal_avd/images/win11-avd-golden/versions/1.0.3"

# … or track the latest version by targeting the image definition:
source_image_id = "/subscriptions/.../resourceGroups/rg-avd-shared/providers/Microsoft.Compute/galleries/gal_avd/images/win11-avd-golden"
```

- **Trusted Launch** is inherited from the gallery **image definition** (its
  `security_type`). Keep `enable_trusted_launch = true` (default) so the VM's
  `secure_boot_enabled`/`vtpm_enabled` match a Trusted Launch image definition —
  no extra configuration on the VM side is required.
- `image` and `image_plan` are ignored while `source_image_id` is set — no need to
  null them out.
- Community/Shared Gallery IDs (e.g. `/CommunityGalleries/<pub>/Images/<img>/Versions/<v>`)
  are also accepted.

## Outputs

- `vm_ids` / `vm_names` / `computer_names` / `principal_ids` / `private_ips` — maps keyed by VM index (`"01"`, `"02"`, ...)
- `resource` — map of full VM resource objects (sensitive)
- `lock_ids` — map of VM suffix => lock ID (empty when `var.lock = null`)
- `role_assignment_ids` — map of `{role_key}:{vm_key}` => assignment ID (empty when `var.role_assignments = {}`)

## Notes

- **AHB + multi-session**: `license_type = "Windows_Client"` is required to consume the M365 entitlement on Win11 multi-session. Default `"None"` causes a silent overpayment.
- **Patch orchestration**: with `patch_mode = "AutomaticByPlatform"` + `bypass_platform_safety_checks_on_user_schedule = true`, Azure Update Manager / a maintenance configuration drives the patch window. Pair with a `Microsoft.Maintenance/configurations` resource at the cluster scope.
- **Token freshness**: the `hostpool_registration_token` input is sensitive and short-lived. Re-apply this module whenever the host pool token rotates (`AvdHostPool` does this automatically via `time_rotating`).
- **DSC artifact**: the AVD DSC URL (`avd_dsc_artifact_url`) defaults to a Microsoft-hosted gallery artifact. Pin to a specific version for reproducible builds.
- **Role assignments**: `var.role_assignments` is applied to every session host VM (cartesian product of role keys × VM keys). For targeted per-VM grants or cross-module scoping, layer `../RoleAssignment` directly.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |
