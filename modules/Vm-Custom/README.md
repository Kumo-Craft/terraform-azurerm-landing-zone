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
