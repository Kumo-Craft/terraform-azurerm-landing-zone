# KeyVaultStack

Composes a Key Vault + Private Endpoint via the canonical sibling modules ([`../KeyVault`](../KeyVault/) and [`../PrivateEndpoint`](../PrivateEndpoint/)). The Resource Group is **caller-provided** via `var.resource_group_name` — same convention as every other leaf module in the repo since v0.2.1.

Use this Stack when you want the KV + PE wired together as a single unit (one resource group, one Private Endpoint per Key Vault). For a bare Key Vault without PE, consume [`../KeyVault`](../KeyVault/) directly.

## Breaking changes

### v0.2.2

**The Stack no longer creates its own resource group.** The `create_resource_group`, `lock`, and `role_assignments` (RG-level) variables have been removed. `resource_group_name` is now required.

Callers that previously used `create_resource_group = true` must add the following `removed` blocks in their Terragrunt root config before applying:

```hcl
removed {
  from = module.keyvaultstack.azurerm_resource_group.this
  lifecycle { destroy = false }
}

removed {
  from = module.keyvaultstack.module.lock
  lifecycle { destroy = false }
}

removed {
  from = module.keyvaultstack.module.rg_role_assignments
  lifecycle { destroy = false }
}
```

Apply **once** with these blocks present, then delete them. They tell Terraform: "these resources are gone from the module config but DO NOT destroy them in Azure". Callers that already used `create_resource_group = false` (i.e. already passed `resource_group_name` from elsewhere) need none of these `removed` blocks — those module addresses were never in their state.

The downstream consumer is now expected to wire the RG, its lock, and its role assignments via a [`../ResourceGroup`](../ResourceGroup/) module instance ahead of this Stack.

**`assign_rbac_to_current_user` default changed from `true` to `false`** to align with the canonical [`../KeyVault`](../KeyVault/) secure-by-default posture. Callers that depended on the auto-RBAC behavior must now either set `assign_rbac_to_current_user = true` explicitly, or grant their Terraform SPN `Key Vault Administrator` inherited from the Management Group / Subscription scope (the recommended Azure-native pattern). See [`../KeyVault/README.md`](../KeyVault/README.md#prerequisites) for the trade-off discussion.

## Usage

### Standalone

```hcl
module "key_vault_stack" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/KeyVaultStack?ref=v0.2.2"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "apim"
  location             = "germanywestcentral"

  resource_group_name  = "rg-api-prod-gwc-apim"
  subnet_id            = "/subscriptions/.../subnets/snet-api-prod-gwc-pe"
  private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.vaultcore.azure.net"]

  # Optional Entra group with KV Administrator at the KV scope —
  # preferred over assign_rbac_to_current_user for pipeline flows.
  kv_admin_group_object_id = "00000000-0000-0000-0000-000000000000"

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/KeyVaultStack"
}

dependency "rg" {
  config_path = "../resource-group"
}

dependency "subnet" {
  config_path = "../network-shared"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "kv"
  kv_suffix            = "002"
  location             = include.root.inputs.location

  resource_group_name = dependency.rg.outputs.names["apim"]
  subnet_id           = dependency.subnet.outputs.subnet_ids[include.sub.locals.networks.corp_apimanager.subnets.kv.name]

  assign_rbac_to_current_user   = false
  public_network_access_enabled = false

  tags = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subscription_acronym | Subscription acronym (e.g. api, mgm) | `string` | -- | Yes |
| environment | Environment (e.g. prod, nprd) | `string` | -- | Yes |
| region_code | Region code (e.g. gwc, weu) | `string` | -- | Yes |
| workload | Workload name. Keep short (KV max 24 chars). | `string` | -- | Yes |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | RG to deploy the KV + PE in. Caller-provided. | `string` | -- | Yes |
| subnet_id | Subnet ID for the Key Vault Private Endpoint | `string` | -- | Yes |
| kv_suffix | Suffix for KV/PE name. If null, uses workload. | `string` | `null` | No |
| kv_name | Explicit Key Vault name (3-24 chars). If null, computed. | `string` | `null` | No |
| tenant_id | Azure AD tenant ID (auto-detected if null) | `string` | `null` | No |
| sku_name | SKU: standard or premium | `string` | `"premium"` | No |
| enable_rbac | Enable RBAC authorization | `bool` | `true` | No |
| assign_rbac_to_current_user | Assign KV Administrator to deployer (forwarded to canonical KV) | `bool` | `false` | No |
| kv_admin_group_object_id | Entra group OID to grant KV Administrator at the KV scope | `string` | `null` | No |
| enabled_for_disk_encryption | Enable Azure Disk Encryption | `bool` | `false` | No |
| enabled_for_deployment | Enable VMs to retrieve certificates | `bool` | `false` | No |
| enabled_for_template_deployment | Enable ARM templates to retrieve secrets | `bool` | `false` | No |
| soft_delete_retention_days | Soft delete retention (7-90 days) | `number` | `90` | No |
| purge_protection_enabled | Enable purge protection (IRREVERSIBLE) | `bool` | `true` | No |
| public_network_access_enabled | Enable public network access | `bool` | `false` | No |
| network_acls | Network ACLs configuration | `object({...})` | `null` | No |
| private_dns_zone_ids | Private DNS Zone IDs for the PE | `list(string)` | `null` | No |
| pe_private_ip_address | Static private IP for the PE | `string` | `null` | No |
| pe_custom_network_interface_name | Custom NIC name for the PE | `string` | `null` | No |
| tags | Tags to apply to all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | Passthrough of `var.resource_group_name` (kept for backward compat) |
| key_vault_id | The Key Vault resource ID |
| key_vault_name | The Key Vault name |
| key_vault_uri | The Key Vault URI |
| key_vault_tenant_id | The Key Vault tenant ID |
| key_vault_resource | Complete Key Vault resource object |
| private_endpoint_id | The Private Endpoint resource ID |
| private_endpoint_name | The Private Endpoint name |
| private_endpoint_ip | The private IP of the PE |

> **Note**: `resource_group_id` and `private_endpoint_connection_status` outputs were removed in v0.2.2 — the Stack no longer owns the RG and no longer reads the PE connection status via a data source. Get the RG id from your upstream `../ResourceGroup` module instance.
