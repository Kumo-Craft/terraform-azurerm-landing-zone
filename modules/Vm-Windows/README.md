# Vm-Windows

Windows VM module: NIC + Windows VM with Entra ID login, System/User-Assigned managed identities, optional CMK disk encryption, optional data disks, and boot diagnostics.

The local admin user is created at provisioning (Azure constraint — cannot be disabled) with a password sourced from Key Vault. Primary access is via **Entra ID** through the `AADLoginForWindows` extension; the local admin is intended for break-glass only.

## Usage

### Standalone

```hcl
module "vm_app" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/Vm-Windows?ref=v0.2.72"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "app"

  location            = "germanywestcentral"
  resource_group_name = "rg-api-prod-gwc-app"
  subnet_id           = "/subscriptions/.../subnets/snet-..."

  vm_count = 2
  vm_size  = "Standard_D4s_v5"

  admin_password_kv_id       = "/subscriptions/.../vaults/kv-api-prod-gwc-app"
  admin_password_secret_name = "vm-local-admin-password"

  user_assigned_identity_ids = [
    "/subscriptions/.../userAssignedIdentities/mi-api-prod-gwc-app",
  ]

  disk_encryption_set_id = "/subscriptions/.../diskEncryptionSets/des-api-prod-gwc-app"

  data_disks = {
    data01 = {
      disk_size_gb = 128
      lun          = 0
    }
    logs01 = {
      disk_size_gb         = 64
      lun                  = 1
      storage_account_type = "StandardSSD_LRS"
      caching              = "None"
    }
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/Vm-Windows"
}

dependency "rg"     { config_path = "../rg-app" }
dependency "subnet" { config_path = "../snet-app" }
dependency "kv"     { config_path = "../kv-app" }

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  location             = include.root.inputs.location
  workload             = "app"

  resource_group_name = dependency.rg.outputs.name
  subnet_id           = dependency.subnet.outputs.id

  admin_password_kv_id       = dependency.kv.outputs.id
  admin_password_secret_name = "vm-local-admin-password"

  data_disks = {
    data01 = { disk_size_gb = 128, lun = 0 }
  }

  tags = include.root.inputs.common_tags
}
```

## Naming Convention

| Resource    | Pattern                                                              |
|-------------|----------------------------------------------------------------------|
| VM          | `vm-{subscription_acronym}-{environment}-{region_code}-{workload}-{NN}` |
| NIC         | `nic-{...}-{NN}`                                                     |
| OS Disk     | `osdisk-vm-{...}-{NN}`                                               |
| Data Disk   | `disk-vm-{...}-{NN}-{disk_key}`                                      |
| Computer    | `{computer_name_prefix or workload+env}{NN}` — max 15 NetBIOS chars  |

## Required Inputs

| Name | Description |
|---|---|
| `subscription_acronym`, `environment`, `region_code`, `workload` | Naming components |
| `location` | Azure region |
| `resource_group_name` | Resource group name |
| `subnet_id` | Subnet resource ID for the NIC |
| `admin_password_kv_id` | Key Vault holding the local admin password |
| `admin_password_secret_name` | Name of the password secret in Key Vault |

## Optional Inputs

| Name | Default | Description |
|---|---|---|
| `vm_count` | `1` | Number of VMs (1–100) |
| `vm_size` | `Standard_D4s_v5` | VM SKU |
| `availability_zones` | `["1","2","3"]` | Zones for round-robin placement |
| `image` | WS2022 Datacenter Azure Edition | Marketplace image reference |
| `os_disk` | Premium_LRS / 128 GiB / ReadWrite | OS disk configuration |
| `user_assigned_identity_ids` | `[]` | UAMI resource IDs to attach (System is always on) |
| `disk_encryption_set_id` | `null` | CMK Disk Encryption Set for OS + data disks |
| `data_disks` | `{}` | Map of data disks (size, lun, caching, sku, create_option, public_network_access_enabled). Public network access defaults to `false` — secure-by-default (CKV_AZURE_251) |
| `boot_diagnostics_enabled` | `true` | Enable boot diagnostics (managed by default) |
| `enable_trusted_launch` | `true` | vTPM + Secure Boot |
| `license_type` | `None` | AHB license type (`None` = pay-as-you-go; set `Windows_Server` only with valid SA entitlement) |
| `patch_mode` | `AutomaticByPlatform` | Azure Update Manager mode |
| `hotpatching_enabled` | `false` | Hotpatching (Server 2022 DC Azure Edition only) |

## Outputs

| Name | Description |
|---|---|
| `vm_ids` | Map of VM suffix → VM resource ID |
| `vm_names` | Map of VM suffix → VM name |
| `computer_names` | Map of VM suffix → Windows hostname |
| `nic_ids` | Map of VM suffix → NIC resource ID |
| `private_ips` | Map of VM suffix → private IP |
| `principal_ids` | Map of VM suffix → SystemAssigned identity principal ID (for RBAC) |
| `data_disk_ids` | Map of `{vm_suffix}-{disk_key}` → managed disk ID |

## Breaking Changes

### v0.2.72 — `license_type` default changed from `"Windows_Server"` to `"None"`

**Who is affected**: callers that relied on the previous implicit `"Windows_Server"` default to activate Azure Hybrid Benefit (AHB) pricing without explicitly setting `license_type`.

**Migration recipe**: before upgrading to v0.2.72, add the following to any module call that requires AHB:

```hcl
license_type = "Windows_Server"
```

This must be set **before** the upgrade to prevent Terraform from changing `license_type` on the VM and potentially triggering an in-place update. Azure changes `license_type` without VM recreation (no downtime), but the change will appear in the plan.

**Callers without a valid Software Assurance entitlement** do not need to take any action — the new default correctly reflects pay-as-you-go pricing and avoids an unintentional compliance violation.

## Notes

- **AAD login only**: the `AADLoginForWindows` extension is always installed. Grant `Virtual Machine User Login` / `Virtual Machine Administrator Login` roles on the VM (or its RG) to the Entra principals that should connect.
- **Admin password**: read from Key Vault at plan time; ignored on subsequent applies (`lifecycle.ignore_changes`). Rotate via `az vm reset` out of band.
- **CMK encryption**: pass `disk_encryption_set_id` to encrypt OS + data disks with a customer-managed key. The DES principal must have `Reader` + `Key Vault Crypto Service Encryption User` on the wrapping key.
- **Data disks**: replicated across every VM in `vm_count`. LUNs must be unique within the map. The disk name pattern includes the VM suffix so disks are unambiguous in the RG.

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
| [azurerm_managed_disk.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_disk) | resource |
| [azurerm_network_interface.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_virtual_machine_data_disk_attachment.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_data_disk_attachment) | resource |
| [azurerm_virtual_machine_extension.entra_join](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_extension) | resource |
| [azurerm_windows_virtual_machine.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/windows_virtual_machine) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_key_vault_secret.admin_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| admin\_password\_kv\_id | Key Vault resource ID holding the local admin password secret. | `string` | n/a | yes |
| admin\_password\_secret\_name | Name of the Key Vault secret holding the local admin password. | `string` | n/a | yes |
| location | ############################################################## REQUIRED ############################################################## | `string` | n/a | yes |
| resource\_group\_name | n/a | `string` | n/a | yes |
| subnet\_id | Subnet resource ID where the NIC(s) will be deployed. | `string` | n/a | yes |
| accelerated\_networking\_enabled | Enable Accelerated Networking on the VM NIC. Set false for sizes that do not support SR-IOV. | `bool` | `true` | no |
| admin\_username | Local admin username (created at provisioning; intended for break-glass only — primary access is Entra ID). | `string` | `"azureadmin"` | no |
| availability\_zones | Zones to spread VMs across (round-robin). Empty list = no zone placement. | `list(string)` | <pre>[<br>  "1",<br>  "2",<br>  "3"<br>]</pre> | no |
| boot\_diagnostics\_enabled | Enable boot diagnostics. Uses Azure-managed storage unless boot\_diagnostics\_storage\_account\_uri is set. | `bool` | `true` | no |
| boot\_diagnostics\_storage\_account\_uri | Custom storage account primary blob endpoint for boot diagnostics. Null = use Azure-managed storage. | `string` | `null` | no |
| bypass\_platform\_safety\_checks\_on\_user\_schedule | When patch\_mode = AutomaticByPlatform, defer to a user-defined maintenance configuration (Update Manager). | `bool` | `true` | no |
| computer\_name\_prefix | Windows computer name prefix (≤ 13 chars; 2 digits appended → 15 total NetBIOS max). Lowercase alphanumeric. Defaults to '{workload}{env}'. | `string` | `null` | no |
| data\_disks | Data disks to create and attach to every VM. Map key becomes part of the disk name.<br>Each disk is replicated for every VM in vm\_count.<br>- disk\_size\_gb                   : size in GiB<br>- lun                            : LUN (must be unique per VM)<br>- storage\_account\_type           : Standard\_LRS \| StandardSSD\_LRS \| Premium\_LRS \| PremiumV2\_LRS \| UltraSSD\_LRS<br>- caching                        : None \| ReadOnly \| ReadWrite<br>- create\_option                  : Empty \| Copy \| Restore (defaults to Empty)<br>- public\_network\_access\_enabled  : allow SAS export/import over the public internet (defaults to false — secure) | <pre>map(object({<br>    disk_size_gb         = number<br>    lun                  = number<br>    storage_account_type = optional(string, "Premium_LRS")<br>    caching              = optional(string, "ReadWrite")<br>    create_option        = optional(string, "Empty")<br>    # CKV_AZURE_251: secure-by-default — public network access to the disk's<br>    # underlying data (via SAS export/import) is DISABLED by default. Azure<br>    # platform default is true. Attached VM operation, backup/restore, and<br>    # resize are unaffected; only SAS-based public export/import is blocked.<br>    # Set true per-disk only when SAS export over the public internet is required.<br>    public_network_access_enabled = optional(bool, false)<br>  }))</pre> | `{}` | no |
| disk\_encryption\_set\_id | Disk Encryption Set resource ID used to encrypt OS and data disks with a customer-managed key. Null = platform-managed key. | `string` | `null` | no |
| enable\_trusted\_launch | Enable Trusted Launch (vTPM + Secure Boot). Microsoft-recommended for new Windows VMs. | `bool` | `true` | no |
| encryption\_at\_host\_enabled | Enable host-based encryption (encrypts temp disk + OS disk cache at hypervisor layer). CAF secure-by-default = true. Azure platform default is false; setting true on existing VMs requires VM stop/dealloc. Callers with existing non-encrypted VMs should set this to false during transition, then schedule a maintenance window to flip back to true. | `bool` | `true` | no |
| environment | n/a | `string` | `null` | no |
| hotpatching\_enabled | Enable hotpatching where supported (Server 2022 Datacenter Azure Edition). Reduces reboots for security patches. | `bool` | `false` | no |
| image | Marketplace image reference. Default: Windows Server 2022 Datacenter Azure Edition. | <pre>object({<br>    publisher = string<br>    offer     = string<br>    sku       = string<br>    version   = optional(string, "latest")<br>  })</pre> | <pre>{<br>  "offer": "WindowsServer",<br>  "publisher": "MicrosoftWindowsServer",<br>  "sku": "2022-datacenter-azure-edition",<br>  "version": "latest"<br>}</pre> | no |
| license\_type | Azure Hybrid Benefit license type for the Windows VM.<br>Allowed: "Windows\_Client", "Windows\_Server", "None".<br>Default is "None" (pay-as-you-go). Set "Windows\_Server" only if you hold active<br>Software Assurance entitlement — applying AHB without a valid SA licence is a<br>compliance violation under the Microsoft Product Terms.<br>BREAKING CHANGE (v0.2.72): default changed from "Windows\_Server" to "None".<br>Callers relying on the previous implicit AHB default MUST explicitly set<br>license\_type = "Windows\_Server" before upgrading to preserve AHB pricing. | `string` | `"None"` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) applied to each VM. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit VM base name override (escape hatch). If set, bypasses ../Naming. If null, uses the canonical convention via ../Naming submodule. | `string` | `null` | no |
| os\_disk | OS disk configuration. Defaults to Premium\_LRS 128 GiB, ReadWrite caching. | <pre>object({<br>    storage_account_type = optional(string, "Premium_LRS")<br>    caching              = optional(string, "ReadWrite")<br>    disk_size_gb         = optional(number, 128)<br>  })</pre> | `{}` | no |
| patch\_mode | Patch orchestration mode. AutomaticByPlatform integrates with Azure Update Manager.<br>Allowed: "Manual", "AutomaticByOS", "AutomaticByPlatform". | `string` | `"AutomaticByPlatform"` | no |
| region\_code | n/a | `string` | `null` | no |
| role\_assignments | Map of role assignments to apply at each VM scope. Assignments are applied to EVERY VM in the pool (role\_key × vm\_key composite keys). Default principal\_type='ServicePrincipal' for VM-scoped RBAC (e.g. granting access to managed identities). | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | n/a | `string` | `null` | no |
| tags | Tags to apply to all resources created by this module. | `map(string)` | `{}` | no |
| user\_assigned\_identity\_ids | User-Assigned Managed Identity resource IDs to attach to the VM. Empty list = SystemAssigned only. | `list(string)` | `[]` | no |
| vm\_count | Number of Windows VMs to create. | `number` | `1` | no |
| vm\_size | VM size. D4s\_v5 is a sensible general-purpose default. | `string` | `"Standard_D4s_v5"` | no |
| workload | Workload suffix for VM naming (e.g. app, srv, web). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| computer\_names | Map of VM suffix => Windows computer (NetBIOS hostname) |
| data\_disk\_ids | Map of '{vm\_suffix}-{disk\_key}' => managed disk resource ID |
| lock\_ids | Map of VM suffix => management lock ID. Empty map when var.lock is null. |
| nic\_ids | Map of VM suffix => NIC resource ID |
| principal\_ids | Map of VM suffix => SystemAssigned identity principal ID (for RBAC grants) |
| private\_ips | Map of VM suffix => NIC private IP |
| resources | Map of VM suffix => azurerm\_windows\_virtual\_machine resource object. Marked sensitive because the VM object carries the admin\_password attribute. |
| role\_assignment\_ids | Map of composite key ({role\_key}.{vm\_key}) => role assignment ID. Empty map when var.role\_assignments is empty. |
| vm\_ids | Map of VM suffix => VM resource ID |
| vm\_names | Map of VM suffix => VM resource name |
<!-- END_TF_DOCS -->
