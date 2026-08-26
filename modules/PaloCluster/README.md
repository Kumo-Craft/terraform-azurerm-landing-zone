# PaloCluster

Deploys a complete Palo Alto VM-Series firewall cluster on Azure. The caller must supply an existing resource group (`resource_group_name`). Creates an internal Standard Load Balancer with HA ports on the trust subnet, zonal VM-Series instances with three NICs each (management access via vWAN / Bastion — no public IPs), and optional disk encryption with customer-managed keys and Application Insights monitoring.

## Usage

### Standalone

```hcl
module "palo_rg" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/ResourceGroup?ref=v0.2.25"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "palo-obew"
  location             = "germanywestcentral"
  tags                 = { Environment = "Production" }
}

module "palo_cluster" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PaloCluster?ref=v0.2.25"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "palo-obew"
  location             = "germanywestcentral"
  resource_group_name  = module.palo_rg.name

  subnet_mgmt_id    = "/subscriptions/.../subnets/snet-con-prod-gwc-mgmt"
  subnet_untrust_id = "/subscriptions/.../subnets/snet-con-prod-gwc-untrust"
  subnet_trust_id   = "/subscriptions/.../subnets/snet-con-prod-gwc-trust"

  ilb_frontend_ip = "10.238.200.36"

  firewalls = {
    "obew-01" = { mgmt_ip = "10.238.200.4", untrust_ip = "10.238.200.20", trust_ip = "10.238.200.37", zone = "1" }
    "obew-02" = { mgmt_ip = "10.238.200.5", untrust_ip = "10.238.200.21", trust_ip = "10.238.200.38", zone = "2" }
  }

  admin_ssh_public_key   = "ssh-rsa AAAA..."
  enable_disk_encryption = true

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PaloCluster"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "palo-obew"
  location             = include.root.inputs.location
  resource_group_name  = dependency.palo_rg.outputs.name

  subnet_mgmt_id    = dependency.subnet.outputs.subnet_ids["snet-con-prod-gwc-mgmt"]
  subnet_untrust_id = dependency.subnet.outputs.subnet_ids["snet-con-prod-gwc-untrust"]
  subnet_trust_id   = dependency.subnet.outputs.subnet_ids["snet-con-prod-gwc-trust"]

  ilb_frontend_ip = "10.238.200.36"

  firewalls = {
    "obew-01" = { mgmt_ip = "10.238.200.4", untrust_ip = "10.238.200.20", trust_ip = "10.238.200.37", zone = "1" }
    "obew-02" = { mgmt_ip = "10.238.200.5", untrust_ip = "10.238.200.21", trust_ip = "10.238.200.38", zone = "2" }
  }

  admin_ssh_public_key       = get_env("PALO_SSH_PUBLIC_KEY")
  log_analytics_workspace_id = dependency.law.outputs.id
  tags                       = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |
| random | >= 3.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subscription_acronym | Subscription acronym (e.g. con) | `string` | -- | Yes |
| environment | Environment (e.g. prod, nprd) | `string` | -- | Yes |
| region_code | Region code (e.g. gwc) | `string` | -- | Yes |
| workload | Workload / cluster name (e.g. palo-obew, palo-in) | `string` | -- | Yes |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Existing resource group name (caller-provided). v0.2.25+: module no longer creates the RG. | `string` | -- | Yes |
| tags | Tags to assign | `map(string)` | `{}` | No |
| subnet_mgmt_id | Management subnet ID | `string` | -- | Yes |
| subnet_untrust_id | Untrust subnet ID | `string` | -- | Yes |
| subnet_trust_id | Trust subnet ID | `string` | -- | Yes |
| ilb_frontend_ip | Static private IP for the ILB frontend in the trust subnet | `string` | -- | Yes |
| ilb_probe_port | ILB health probe port | `number` | `443` | No |
| ilb_probe_threshold | Consecutive failures before unhealthy | `number` | `2` | No |
| ilb_probe_interval | Health probe interval in seconds | `number` | `5` | No |
| firewalls | Map of firewall instances. Key = name suffix, value = NIC IPs and zone. | `map(object({ mgmt_ip = string, untrust_ip = string, trust_ip = string, zone = optional(string) }))` | -- | Yes |
| vm_size | VM SKU — must be Dsv3+ for encryption_at_host_enabled = true | `string` | `"Standard_DS4_v3"` | No |
| accept_marketplace_agreement | Accept Palo Alto Marketplace agreement (set true on first deploy per subscription) | `bool` | `false` | No |
| vm_image | Palo Alto VM-Series marketplace image | `object({ publisher = string, offer = string, sku = string, version = string })` | Palo Alto defaults | No |
| panos_version | PAN-OS version. Applied as the `PanosVersion` tag on all cluster resources for lifecycle visibility. | `string` | `"11.1.607"` | No |
| admin_username | Admin username for VM-Series instances | `string` | `"panadmin"` | No |
| admin_password | Admin password. Mutually exclusive with admin_ssh_public_key. | `string` | `null` | No |
| admin_ssh_public_key | SSH public key. Mutually exclusive with admin_password. | `string` | `null` | No |
| os_disk_size_gb | OS disk size in GB | `number` | `80` | No |
| os_disk_storage_account_type | OS disk type: Standard_LRS, StandardSSD_LRS, Premium_LRS | `string` | `"Premium_LRS"` | No |
| accelerated_networking | Enable accelerated networking on dataplane NICs | `bool` | `true` | No |
| enable_boot_diagnostics | Enable boot diagnostics for troubleshooting | `bool` | `false` | No |
| boot_diagnostics_storage_uri | Storage account URI for boot diagnostics | `string` | `null` | No |
| enable_disk_encryption | Creates KV + RSA key + DES for CMK disk encryption | `bool` | `true` | No |
| kv_admin_principal_ids | Entra ID principal OIDs (users, groups, SPNs) granted Key Vault Administrator on the cluster KV. **Must include every identity that runs `terragrunt apply`** (pipeline SPN OID, local admins). Omitting the deploying identity causes disk encryption key unwrap failures. | `list(string)` | `[]` | No |
| kv_secrets_readers | Entra ID object IDs granted Key Vault Secrets User | `list(string)` | `[]` | No |
| kv_allowed_ips | Public IPs (CIDR /32) allowed to access the KV | `list(string)` | `[]` | No |
| lock | Optional management lock on the ILB. `kind`: `"CanNotDelete"` or `"ReadOnly"`. `name`: optional override (defaults to `lock-ilb`). | `object({ kind = string, name = optional(string) })` | `null` | No |
| vwan_bgp_peer_ips | Optional list of vWAN virtual hub router BGP peer IPs (from `module.vwan.virtual_hub_router_ips`). Stored as KV secret when `enable_disk_encryption = true`. | `list(string)` | `null` | No |
| vwan_bgp_peer_asn | Optional vWAN virtual hub router BGP ASN (from `module.vwan.virtual_hub_router_asns`). Typically `65515`. Stored as KV secret when set. | `number` | `null` | No |
| encryption_at_host_enabled | Enables Encryption at Host on VMs (hypervisor-level encryption of temp disk, cache, pagefile). Requires subscription feature `Microsoft.Compute/EncryptionAtHost` registered and a compatible VM SKU (Dsv3+/Dsv4+). | `bool` | `true` | No |
| log_analytics_workspace_id | LAW ID for Application Insights. If null, no APPI. | `string` | `null` | No |
| panos_spn_object_id | PAN-OS SPN object ID for custom AppInsights role | `string` | `null` | No |
| bootstrap_storage_account_name | Bootstrap storage account NAME (not ARM ID). If null, no bootstrap. | `string` | `null` | No |
| bootstrap_share_name | File share name for bootstrap | `string` | `null` | No |
| bootstrap_share_directory | Optional subdirectory within the file share | `string` | `null` | No |
| bootstrap_storage_account_access_key | Bootstrap storage account access key | `string` | `null` | No |
| bootstrap_storage_account_sas_token | SAS token alternative to access key (time-limited; takes precedence if set) | `string` | `null` | No |
| bootstrap_storage_account_use_msi | Use VM System-Assigned MSI for bootstrap SA (PAN-OS 10.2+, no credential in custom_data) | `bool` | `false` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | Resource group name (caller-provided passthrough) |
| ilb_id | Internal Load Balancer ID |
| ilb_frontend_ip | Internal Load Balancer frontend IP |
| ilb_backend_pool_id | Internal Load Balancer backend pool ID |
| ilb_lock_ids | Map of ILB Resource Lock IDs (empty map when no lock configured) |
| disk_encryption_set_id | Disk Encryption Set ID (null if no CMK) |
| key_vault_id | Key Vault ID for disk encryption (null if disabled) |
| des_identity_principal_id | DES managed identity principal ID |
| vm_ids | Map of key => VM ID |
| vm_names | Map of key => VM name |
| mgmt_private_ips | Map of key => management private IP |
| trust_private_ips | Map of firewall key => trust NIC private IP. Use for UDR next-hop or vwan BGP peer wiring. |
| untrust_private_ips | Map of firewall key => untrust NIC private IP. Use for external-facing UDR wiring. |
| appinsights_instrumentation_keys | Map of key => APPI instrumentation key (sensitive) |
| appinsights_connection_strings | Map of key => APPI connection string (sensitive) |
| resources | Canonical composite map `{ ilb, vm, des }` for downstream composition (sensitive). `vm` (`id`, `name`, `private_ip_address`, `virtual_machine_id`, `identity`) and `des` (`id`, `name`, `identity`, `key_vault_key_id`) are curated field lists — they omit the provider-deprecated attributes (`vm_agent_platform_updates_enabled` read-only on the VM, `managed_hsm_key_id` on the DES) a raw resource-object output would surface. |

## Breaking changes (v0.2.25)

PaloCluster no longer creates its own resource group. Callers must now supply `resource_group_name` (string, required).

## Breaking changes (v0.2.26)

PaloCluster v0.2.26 is a composition refactor. All Azure resources are preserved — only Terraform state paths change. There is one breaking naming change.

### KV moved block (zero Azure-side change)

The inline `azurerm_key_vault.this` resource has been replaced by `module "kv"` (composed via `../KeyVault`). A `moved {}` block migrates the state path automatically:

```
azurerm_key_vault.this[0]  →  module.kv[0].azurerm_key_vault.this
```

No Azure resource is renamed or destroyed. Callers upgrading from v0.2.25 see only a state migration on the next `terraform plan`.

### ILB rename (BREAKING if using convention naming)

The ILB name now comes from the `../Naming` submodule (slug `lbi-`), replacing the legacy literal-concat pattern (`ilb-`). **If you relied on convention naming (`var.name = null`), the ILB will be renamed in Azure on upgrade** (destroy + recreate of the ILB resource).

To suppress the rename and preserve byte-for-byte compatibility, pin `var.name`:

```hcl
module "palo_cluster" {
  # ...
  name = "ilb-con-prod-gwc-palo-obew-trust"  # legacy name — prevents rename
}
```

### New variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | `string` | `null` | ILB name override (pass to suppress ILB rename on upgrade) |
| `lock` | `object({ kind, name? })` | `null` | Management lock on the ILB |
| `vwan_bgp_peer_ips` | `list(string)` | `null` | vwan hub BGP peer IPs — stored as KV secret when set |
| `vwan_bgp_peer_asn` | `number` | `null` | vwan hub BGP ASN — stored as KV secret when set |

## Breaking changes (v0.2.73)

### Removed: keyless `moved` blocks for `module.kv_admin` and `module.kv_secrets_reader`

These two `moved {}` blocks have been removed because both modules are `for_each`-keyed by caller-supplied principal OIDs. A static `moved` block cannot enumerate dynamic, caller-controlled keys — Terraform would silently ignore or mis-apply it.

Callers who deployed with a version prior to v0.2.73 and have existing state at the **bare** address (before the composition) must run a manual state migration **once** per principal OID:

**`module.kv_admin` (var.kv_admin_principal_ids):**

```sh
terraform state mv \
  'azurerm_role_assignment.kv_admin' \
  'module.kv_admin["<oid>"].azurerm_role_assignment.this'
```

**`module.kv_secrets_reader` (var.kv_secrets_readers):**

```sh
terraform state mv \
  'azurerm_role_assignment.kv_secrets_reader' \
  'module.kv_secrets_reader["<oid>"].azurerm_role_assignment.this'
```

Run one command per OID. If the bare address does not exist in your state (e.g. you deployed first on v0.2.26+), no action is needed.

## Breaking changes (v0.2.91)

### `principal_type` corrected on `module.kv_admin` and `module.kv_secrets_reader`

Both grants previously inherited the `RoleAssignment` module default `principal_type = "ServicePrincipal"`, which was wrong for these principals:

- `var.kv_admin_principal_ids` holds **mixed** users/groups/SPNs → now passes `principal_type = null` (Azure auto-detect).
- `var.kv_secrets_readers` holds **Entra ID group** OIDs → now passes `principal_type = "Group"`.

`principal_type` is `ForceNew` on `azurerm_role_assignment`. The next `terragrunt apply` will **recreate** these role assignments (destroy + create) once. The grants are functionally identical before and after — only the principal-type metadata changes — but expect the resources to show as replaced in the plan.

> Note: with `principal_type = null` on `module.kv_admin`, Azure re-introduces the AAD lookup race on first apply for freshly-created principals. A re-run resolves it. The explicit `"Group"` on `module.kv_secrets_reader` avoids this.

## Composed modules

| Module | Path | Purpose |
|--------|------|---------|
| KeyVault | `../KeyVault` | Cluster Key Vault for DES CMK + secrets |
| Naming | `../Naming` | ILB name (slug `lbi-`) |
| ResourceLock | `../ResourceLock` | Optional management lock on the ILB |
| RoleAssignment | `../RoleAssignment` | KV RBAC (Admin, Crypto, Secrets User) |

### Migration recipe for callers upgrading from v0.2.24 or earlier

If your previous deployment had this module create the RG (the default behavior in v0.2.24 and earlier), follow this 4-step recipe to avoid destroying the existing RG and the resources beneath it (KV + DES + UAI + VMs + NICs + ILB — all the Palo cluster infrastructure):

1. **Move RG ownership to your root config.** Add a `module "palo_rg" { source = "../ResourceGroup" ... }` (or equivalent) to your root. Pass it the SAME name the module previously generated (i.e. `rg-{subscription_acronym}-{environment}-{region_code}-{workload}`).

2. **Add a `removed` block in your root config** to release the RG from PaloCluster state without destroying it Azure-side:

   ```hcl
   removed {
     from = module.palo_cluster.azurerm_resource_group.this
     lifecycle {
       destroy = false
     }
   }
   ```

3. **Run `terraform state mv`** to move the RG into the new owner's state path:

   ```bash
   terraform state mv \
     module.palo_cluster.azurerm_resource_group.this \
     module.palo_rg.azurerm_resource_group.this
   ```

4. **Pass the new RG to PaloCluster**:

   ```hcl
   module "palo_cluster" {
     source              = "..."
     resource_group_name = module.palo_rg.name
     # other args...
   }
   ```

The KV + DES + VMs + NICs + ILB continue to live under the PaloCluster module's address paths and are NOT affected by the RG ownership transfer (they reference the RG by name, not by Terraform resource address).

### `output "resource"` removed

The v0.2.24 module exposed `output "resource"` as the raw `azurerm_resource_group.this` object. This is removed in v0.2.25 (no longer applicable post-RG-drop). Use `output "resource_group_name"` for the RG name reference.

### `output "resource_group_id"` removed

The v0.2.24 module exposed `output "resource_group_id"`. This is removed in v0.2.25. If you need the RG ID, add a `data "azurerm_resource_group" "this"` lookup in your root config.
