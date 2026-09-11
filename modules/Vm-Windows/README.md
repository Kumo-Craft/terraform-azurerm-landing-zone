# Vm-Windows

Windows VM module: NIC + Windows VM with Entra ID login, System/User-Assigned managed identities, optional CMK disk encryption, optional data disks, and boot diagnostics.

The local admin user is created at provisioning (Azure constraint — cannot be disabled) with a password sourced from Key Vault. Primary access is via **Entra ID** through the `AADLoginForWindows` extension; the local admin is intended for break-glass only.

## Usage

### Standalone

```hcl
module "vm_app" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/Vm-Windows?ref=v0.2.72"

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
