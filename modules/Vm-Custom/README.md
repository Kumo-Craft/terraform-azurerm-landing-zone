# Vm-Custom

Deploys one or more **Linux virtual machines** with secure-by-default settings and a **flexible image source** — a marketplace image (with optional purchase plan) **or** a custom / Shared Image Gallery image. Companion to [`Vm-Windows`](../Vm-Windows).

## Best-practice defaults

- **SSH-key authentication** — `disable_password_authentication = true`; password auth is only enabled if you explicitly supply a Key Vault password secret.
- **Microsoft Entra ID SSH login** — `AADSSHLoginForLinux` extension installed by default (pair with the *Virtual Machine User/Administrator Login* roles via `role_assignments`).
- **Trusted Launch** (vTPM + Secure Boot) on by default (Gen2 image/size required).
- **Encryption at host** on by default; optional **CMK** for OS + data disks via a Disk Encryption Set.
- **Azure Update Manager** patching (`patch_mode = AutomaticByPlatform`).
- **SystemAssigned identity** always enabled; NICs never forward IP traffic; zone-spread across `["1","2","3"]` by default.

## Image source

`source_image_id` (custom / Shared Image Gallery / community gallery) **takes precedence** when set — the marketplace `image`/`image_plan` are then ignored. Otherwise the marketplace `image` is used (default: Ubuntu Server 22.04 LTS Gen2).

## Usage

### Marketplace image (default Ubuntu), Entra SSH login

```hcl
module "vm" {
  source = "../Vm-Custom"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "app"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-app"
  subnet_id            = "/subscriptions/.../subnets/snet-app"

  vm_count             = 2
  vm_size              = "Standard_D2s_v5"
  admin_ssh_public_key = file("~/.ssh/id_ed25519.pub")

  # Grant Entra SSH login to a group (works with AADSSHLoginForLinux).
  role_assignments = {
    ssh_admins = {
      role_definition_id_or_name = "Virtual Machine Administrator Login"
      principal_id               = "00000000-0000-0000-0000-000000000000"
      principal_type             = "Group"
    }
  }

  data_disks = {
    data01 = { disk_size_gb = 256, lun = 0 }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Custom / Shared Image Gallery image

```hcl
module "vm" {
  source = "../Vm-Custom"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "app"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-app"
  subnet_id            = "/subscriptions/.../subnets/snet-app"

  admin_ssh_public_key = file("~/.ssh/id_ed25519.pub")

  # Takes precedence over the marketplace image.
  source_image_id = "/subscriptions/.../galleries/cg1/images/hardened-ubuntu/versions/1.0.0"
}
```

### Paid marketplace image (plan)

```hcl
  image = {
    publisher = "<publisher>"
    offer     = "<offer>"
    sku       = "<sku>"
    version   = "latest"
  }
  image_plan = {
    publisher = "<publisher>"
    product   = "<offer>"
    name      = "<sku>"
  }
  # az vm image terms accept --publisher <publisher> --offer <offer> --plan <sku>
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Key Inputs

| Name | Default | Description |
|---|---|---|
| `name` | `null` | Explicit VM base name override — bypasses `../Naming` |
| `subscription_acronym` / `environment` / `region_code` / `workload` | `null` | Convention naming components (required unless `name` is set) |
| `location` / `resource_group_name` / `subnet_id` | -- | Required |
| `admin_ssh_public_key` | -- | **Required.** ssh-rsa (≥2048-bit) or ssh-ed25519 public key |
| `admin_username` | `"azureadmin"` | Local admin username |
| `vm_count` | `1` | Number of VMs |
| `vm_size` | `Standard_D2s_v5` | VM size |
| `availability_zones` | `["1","2","3"]` | Round-robin zone placement (empty = none) |
| `image` | Ubuntu 22.04 LTS Gen2 | Marketplace image (ignored if `source_image_id` set) |
| `image_plan` | `null` | Marketplace plan for paid offers |
| `source_image_id` | `null` | Custom / Shared Image Gallery image ID — takes precedence |
| `os_disk` | Premium_LRS 64 GiB | OS disk config |
| `data_disks` | `{}` | Map of data disks (size, lun, type, caching) — created per VM |
| `enable_trusted_launch` | `true` | vTPM + Secure Boot |
| `encryption_at_host_enabled` | `true` | Host-level encryption |
| `disk_encryption_set_id` | `null` | CMK for OS + data disks |
| `patch_mode` | `"AutomaticByPlatform"` | `AutomaticByPlatform` or `ImageDefault` |
| `license_type` | `null` | RHEL_*/SLES_*/UBUNTU_PRO |
| `entra_ssh_login_enabled` | `true` | Install AADSSHLoginForLinux extension |
| `admin_password_kv_id` / `admin_password_secret_name` | `null` | Optional Key Vault password secret (enables password auth) — set together |
| `user_assigned_identity_ids` | `[]` | UAMIs to attach (SystemAssigned always on) |
| `boot_diagnostics_enabled` | `true` | Boot diagnostics (Azure-managed storage by default) |
| `lock` | `null` | Per-VM management lock (CanNotDelete/ReadOnly) |
| `role_assignments` | `{}` | RBAC applied to every VM |
| `tags` | `{}` | Tags |

## Outputs

| Name | Description |
|------|-------------|
| vm_ids | Map of VM suffix => VM resource ID |
| vm_names | Map of VM suffix => VM name |
| computer_names | Map of VM suffix => Linux hostname |
| nic_ids | Map of VM suffix => NIC resource ID |
| private_ips | Map of VM suffix => NIC private IP |
| principal_ids | Map of VM suffix => SystemAssigned identity principal ID |
| data_disk_ids | Map of `{vm_suffix}-{disk_key}` => managed disk ID |
| resources | Map of VM suffix => full VM resource object (sensitive) |
| lock_ids | Map of VM suffix => management lock ID |
| role_assignment_ids | Map of `{role_key}.{vm_key}` => role assignment ID |

## Notes

- **Entra SSH login** requires RBAC: grant *Virtual Machine Administrator Login* or *Virtual Machine User Login* (via `role_assignments` or inherited from a higher scope). Connect with `az ssh vm -n <vm> -g <rg>`.
- **VM name length.** The shared `../Naming` submodule caps the `virtual_machine` type at 15 chars (NetBIOS heritage); long prefixes truncate the workload segment. Pass an explicit `name` if you need the full identifier in the VM resource name.
- **Trusted Launch** requires a Gen2 / Trusted-Launch-capable image and VM size — set `enable_trusted_launch = false` for Gen1 images.
- **Encryption at host** requires the `EncryptionAtHost` feature registered on the subscription.

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_linux_virtual_machine.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_managed_disk.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_disk) | resource |
| [azurerm_network_interface.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_virtual_machine_data_disk_attachment.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_data_disk_attachment) | resource |
| [azurerm_virtual_machine_extension.entra_ssh_login](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_extension) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_key_vault_secret.admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| admin\_ssh\_public\_key | SSH public key (ssh-rsa >= 2048-bit or ssh-ed25519) written to /home/<admin\_username>/.ssh/authorized\_keys. | `string` | n/a | yes |
| location | Azure region. | `string` | n/a | yes |
| resource\_group\_name | Resource group name. | `string` | n/a | yes |
| subnet\_id | Subnet ID for the VM NIC(s). | `string` | n/a | yes |
| accelerated\_networking\_enabled | Enable Accelerated Networking on the VM NIC. Set false for sizes that do not support SR-IOV. | `bool` | `true` | no |
| admin\_password\_kv\_id | Optional. Key Vault resource ID holding a local admin password secret. When set (with admin\_password\_secret\_name), password authentication is ENABLED alongside the SSH key. Leave null to keep password auth disabled (recommended). | `string` | `null` | no |
| admin\_password\_secret\_name | Optional. Name of the Key Vault secret holding the local admin password. Required when admin\_password\_kv\_id is set. | `string` | `null` | no |
| admin\_username | Local admin username for the Linux VM. | `string` | `"azureadmin"` | no |
| availability\_zones | Zones to spread VMs across (round-robin). Empty list = no zone placement. | `list(string)` | <pre>[<br>  "1",<br>  "2",<br>  "3"<br>]</pre> | no |
| boot\_diagnostics\_enabled | Enable boot diagnostics. Uses Azure-managed storage unless boot\_diagnostics\_storage\_account\_uri is set. | `bool` | `true` | no |
| boot\_diagnostics\_storage\_account\_uri | Custom storage account primary blob endpoint for boot diagnostics. Null = use Azure-managed storage. | `string` | `null` | no |
| bypass\_platform\_safety\_checks\_on\_user\_schedule | When patch\_mode = AutomaticByPlatform, defer to a user-defined maintenance configuration (Update Manager). | `bool` | `true` | no |
| computer\_name\_prefix | Optional explicit Linux hostname prefix (the per-VM index is appended). If null, derived from workload/environment or the VM base name. | `string` | `null` | no |
| data\_disks | Data disks to create and attach to every VM. Map key becomes part of the disk name.<br>Each disk is replicated for every VM in vm\_count.<br>- disk\_size\_gb          : size in GiB<br>- lun                   : LUN (must be unique per VM)<br>- storage\_account\_type  : Standard\_LRS \| StandardSSD\_LRS \| Premium\_LRS \| PremiumV2\_LRS \| UltraSSD\_LRS<br>- caching               : None \| ReadOnly \| ReadWrite<br>- create\_option         : Empty \| Copy \| Restore (defaults to Empty) | <pre>map(object({<br>    disk_size_gb         = number<br>    lun                  = number<br>    storage_account_type = optional(string, "Premium_LRS")<br>    caching              = optional(string, "ReadWrite")<br>    create_option        = optional(string, "Empty")<br>  }))</pre> | `{}` | no |
| disk\_access\_id | Disk Access resource ID enabling private-endpoint SAS access to data disks. Only applied when disk\_network\_access\_policy = 'AllowPrivate'. | `string` | `null` | no |
| disk\_encryption\_set\_id | Disk Encryption Set resource ID used to encrypt OS and data disks with a customer-managed key. Null = platform-managed key. | `string` | `null` | no |
| disk\_network\_access\_policy | Network access policy for data disks (SAS import/export). 'DenyAll' (secure default — no SAS export/import at all), 'AllowPrivate' (SAS only via a Disk Access private endpoint — requires disk\_access\_id), or 'AllowAll'. | `string` | `"DenyAll"` | no |
| disk\_public\_network\_access\_enabled | Whether data disks are reachable via public network for SAS import/export. Secure default false (blocks public data-plane access — CKV\_AZURE\_251). | `bool` | `false` | no |
| enable\_trusted\_launch | Enable Trusted Launch (vTPM + Secure Boot). Microsoft-recommended for Gen2 Linux VMs. Requires a Gen2/Trusted Launch capable image and VM size. | `bool` | `true` | no |
| encryption\_at\_host\_enabled | Enable host-based encryption (encrypts temp disk + OS/data disk caches at the hypervisor layer). CAF secure-by-default = true. Azure platform default is false; enabling on existing VMs requires stop/dealloc. Requires the EncryptionAtHost feature to be registered on the subscription. | `bool` | `true` | no |
| entra\_ssh\_login\_enabled | Install the AADSSHLoginForLinux extension to enable Microsoft Entra ID SSH login (RBAC: Virtual Machine User/Administrator Login). Requires the SystemAssigned identity (always enabled by this module). | `bool` | `true` | no |
| environment | n/a | `string` | `null` | no |
| image | Marketplace image reference. Default: Ubuntu Server 22.04 LTS (Gen2). Ignored when source\_image\_id is set. | <pre>object({<br>    publisher = string<br>    offer     = string<br>    sku       = string<br>    version   = optional(string, "latest")<br>  })</pre> | <pre>{<br>  "offer": "0001-com-ubuntu-server-jammy",<br>  "publisher": "Canonical",<br>  "sku": "22_04-lts-gen2",<br>  "version": "latest"<br>}</pre> | no |
| image\_plan | Marketplace plan for images that require purchase terms (paid/3rd-party offers). Leave null for first-party images (Ubuntu, RHEL PAYG, etc.). Ignored when source\_image\_id is set. Accept terms once: `az vm image terms accept`. | <pre>object({<br>    name      = string<br>    publisher = string<br>    product   = string<br>  })</pre> | `null` | no |
| license\_type | Optional Linux license type / Azure Hybrid Benefit. Allowed: RHEL\_BYOS, RHEL\_BASE, RHEL\_EUS, RHEL\_SAPAPPS, RHEL\_SAPHA, RHEL\_BASESAPAPPS, RHEL\_BASESAPHA, SLES\_BYOS, SLES\_SAP, SLES\_HPC, UBUNTU\_PRO. Null = none (PAYG). | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) applied to each VM. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit VM base name override (escape hatch). If set, bypasses ../Naming. If null, uses the canonical convention via ../Naming submodule. | `string` | `null` | no |
| os\_disk | OS disk configuration. Defaults to Premium\_LRS 64 GiB, ReadWrite caching. | <pre>object({<br>    storage_account_type = optional(string, "Premium_LRS")<br>    caching              = optional(string, "ReadWrite")<br>    disk_size_gb         = optional(number, 64)<br>  })</pre> | `{}` | no |
| patch\_mode | Patch orchestration mode for Linux. Allowed: 'AutomaticByPlatform' (integrates with Azure Update Manager) or 'ImageDefault'. | `string` | `"AutomaticByPlatform"` | no |
| region\_code | n/a | `string` | `null` | no |
| role\_assignments | Map of role assignments to apply at each VM scope (applied to EVERY VM in the pool). Use 'Virtual Machine Administrator Login' / 'Virtual Machine User Login' with Entra SSH login. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| source\_image\_id | Resource ID of a custom image, Shared/Community Image Gallery image, or gallery image version. When set, takes precedence over the marketplace `image`/`image_plan`. | `string` | `null` | no |
| subscription\_acronym | n/a | `string` | `null` | no |
| tags | Tags to apply to all resources created by this module. | `map(string)` | `{}` | no |
| user\_assigned\_identity\_ids | User-Assigned Managed Identity resource IDs to attach to the VM. Empty list = SystemAssigned only. | `list(string)` | `[]` | no |
| vm\_count | Number of Linux VMs to create. | `number` | `1` | no |
| vm\_size | VM size. D2s\_v5 is a sensible general-purpose Linux default. | `string` | `"Standard_D2s_v5"` | no |
| workload | n/a | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| computer\_names | Map of VM suffix => Linux hostname |
| data\_disk\_ids | Map of '{vm\_suffix}-{disk\_key}' => managed disk resource ID |
| lock\_ids | Map of VM suffix => management lock ID. Empty map when var.lock is null. |
| nic\_ids | Map of VM suffix => NIC resource ID |
| principal\_ids | Map of VM suffix => SystemAssigned identity principal ID (for RBAC grants) |
| private\_ips | Map of VM suffix => NIC private IP |
| resources | Map of VM suffix => azurerm\_linux\_virtual\_machine resource object. Marked sensitive because the VM object can carry the admin\_password attribute. |
| role\_assignment\_ids | Map of composite key ({role\_key}.{vm\_key}) => role assignment ID. Empty map when var.role\_assignments is empty. |
| vm\_ids | Map of VM suffix => VM resource ID |
| vm\_names | Map of VM suffix => VM resource name |
<!-- END_TF_DOCS -->
