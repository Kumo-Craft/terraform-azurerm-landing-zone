# ContainerRegistry

Deploys an Azure Container Registry (ACR) with Premium SKU, zone redundancy, geo-replication, network rules, optional management lock, and flexible RBAC role assignments. Names follow the `cr{subscription_acronym}{environment}{region_code}{workload}` convention (no hyphens).

## Usage

### Standalone

```hcl
module "container_registry" {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/ContainerRegistry?ref=v0.2.89"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "001"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-acr"

  sku                           = "Premium"
  public_network_access_enabled = false

  role_assignments = {
    aks_kubelet_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = "00000000-0000-0000-0000-000000000000"
      description                = "AKS kubelet identity"
    }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ContainerRegistry"
}

inputs = {
  subscription_acronym          = include.sub.locals.subscription_acronym
  environment                   = include.root.inputs.environment
  region_code                   = include.root.inputs.region_code
  workload                      = "001"
  location                      = include.root.inputs.location
  resource_group_name           = dependency.rg.outputs.name
  public_network_access_enabled = false

  role_assignments = {
    aks_kubelet_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = dependency.id_kubelet.outputs.principal_id
    }
  }

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
| name | Explicit registry name (5-50 alphanumeric). If null, computed. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload suffix. No hyphens (ACR alphanumeric only). | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| sku | Registry SKU: Basic, Standard, Premium | `string` | `"Premium"` | No |
| admin_enabled | Enable admin account (not recommended) | `bool` | `false` | No |
| public_network_access_enabled | Enable public network access | `bool` | `false` | No |
| zone_redundancy_enabled | Enable zone redundancy (**Premium only** — null-guarded to `null` on Basic/Standard, so the `true` default is harmless). | `bool` | `true` | No |
| data_endpoint_enabled | Enable data endpoint (**Premium only** — null-guarded to `null` on Basic/Standard, so the `true` default is harmless). | `bool` | `true` | No |
| georeplications | Geo-replication config (Premium only). Supports `regional_endpoint_enabled`. | `list(object({...}))` | `[]` | No |
| network_rule_set | Network rule set (**Premium only**). Supports `ip_rule` list for IP allow-listing. `ip_rule.action` must be `"Allow"` (only accepted value). | `object({...})` | `null` | No |
| anonymous_pull_enabled | Allow unauthenticated repository read (**Standard/Premium only** — a precondition rejects `true` on Basic SKU). | `bool` | `false` | No |
| export_policy_enabled | Allow exporting repository artifacts (acr import / export pipeline). **Defaults to `false` (secure-by-default).** Requires `public_network_access_enabled = false` when set to `false` — see [export/public-network constraint](#exportpublic-network-constraint). Premium SKU only. | `bool` | `false` | No |
| retention_policy_in_days | Auto-purge untagged manifests after N days (1-365, Premium only). null = never. | `number` | `null` | No |
| trust_policy_enabled | Enable content trust / image signing (Premium only) | `bool` | `false` | No |
| quarantine_policy_enabled | Enable quarantine policy — images quarantined until scanned (Premium only) | `bool` | `false` | No |
| network_rule_bypass_option | Allow trusted Azure services to bypass network rules. "AzureServices" or "None". | `string` | `"AzureServices"` | No |
| identity_ids | UAMI IDs to attach to the registry. Required if customer_managed_key is set. | `set(string)` | `[]` | No |
| customer_managed_key | CMK encryption (Premium only). Object: `{ key_vault_key_id, identity_client_id }` | `object({...})` | `null` | No |
| diagnostic_setting | Optional diag setting → LAW. Object: `{ name?, log_analytics_workspace_id, categories?, metrics_enabled? }` | `object({...})` | `null` | No |
| role_assignments | Map of role assignments on the ACR. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| private_endpoints | Map of Private Endpoints (sub-resource `registry`). **Premium only.** Per-entry: `subnet_id` (req), `name`, `private_dns_zone_ids`, `private_ip_address`, `member_name`, `custom_network_interface_name`, `tags`. | `map(object({...}))` | `{}` | No |
| lock | Management lock (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags | `map(string)` | `{}` | No |

## SKU-gating

| Feature | SKU requirement | Enforcement |
|---------|----------------|-------------|
| `customer_managed_key` | Premium | precondition |
| `retention_policy_in_days` | Premium | precondition + null-guard |
| `trust_policy_enabled` | Premium | precondition + null-guard |
| `quarantine_policy_enabled` | Premium | precondition + null-guard |
| `export_policy_enabled` | Premium | null-guard |
| `georeplications` | Premium | precondition |
| `network_rule_set` | Premium | precondition |
| `zone_redundancy_enabled` | Premium | null-guarded (`null` on Basic/Standard — `true` default is harmless) |
| `data_endpoint_enabled` | Premium | null-guarded (`null` on Basic/Standard — `true` default is harmless) |
| `anonymous_pull_enabled = true` | Standard or Premium | precondition |

A precondition in the resource `lifecycle` block catches misconfigurations at plan time.

### Export/public-network constraint

Azure enforces that `export_policy_enabled = false` is only valid when `public_network_access_enabled = false` ([MS Learn — data-loss-prevention](https://aka.ms/acr/export-policy)). This module adds a plan-time precondition that enforces this coupling so callers get a clear error rather than an API rejection.

The module defaults are `export_policy_enabled = false` and `public_network_access_enabled = false`, so default callers pass without any action. Only a caller who sets `public_network_access_enabled = true` while keeping `export_policy_enabled = false` (or not setting it) will trip the precondition.

To enable public access and artifact export together:

```hcl
public_network_access_enabled = true
export_policy_enabled         = true
```

To keep public access enabled with export disabled — this is **not permitted by Azure** and is rejected by the precondition. You must disable public network access first.

### CMK example

```hcl
identity_ids = [azurerm_user_assigned_identity.acr.id]

customer_managed_key = {
  key_vault_key_id   = azurerm_key_vault_key.acr_cmk.versionless_id
  identity_client_id = azurerm_user_assigned_identity.acr.client_id
}
```

The UAMI must hold `Key Vault Crypto User` on the Key Vault hosting the key. Use the **versionless** key URI to enable rotation without recreating the registry.

### Diagnostic settings

```hcl
diagnostic_setting = {
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.platform.id
  # default categories: ContainerRegistryRepositoryEvents + ContainerRegistryLoginEvents
  # default metrics_enabled: true
}
```

## BREAKING CHANGES

### Next release — `export_policy_enabled` default changed `true` → `false` (SOFT BREAKING)

**What changed:** `export_policy_enabled` now defaults to `false` (secure-by-default). Previously it defaulted to `true`.

**Who is affected:**

1. **Callers who relied on the implicit `true` default and have public network access enabled (`public_network_access_enabled = true`):**
   The new precondition will reject this combination at plan time with a clear error. You must explicitly set `export_policy_enabled = true`:
   ```hcl
   export_policy_enabled         = true
   public_network_access_enabled = true
   ```

2. **Callers who want to keep export disabled (`false`) and currently have public access enabled:**
   This combination is **not permitted by Azure** — you must also disable public network access:
   ```hcl
   export_policy_enabled         = false
   public_network_access_enabled = false  # required
   ```

3. **Callers with the default (no `export_policy_enabled` set) and `public_network_access_enabled = false` (the module default):**
   No action required — these callers already satisfy both conditions and continue to work.

**Migration recipe:** Run `terraform plan` after upgrading. Any plan error mentioning `export_policy_enabled` will tell you exactly what combination to fix.

### v0.2.83 — moved block removed (manual state migration may be required)

The static `moved` block that attempted to migrate `azurerm_role_assignment.this` to
`module.role_assignments` has been removed. It was invalid because `module.role_assignments`
is `for_each`-keyed by `var.role_assignments` (dynamic keys) — Terraform cannot enumerate
for_each instance keys at moved-block parse time (Truth #3 pattern).

If your Terraform state contains resources at the old address
`module.<caller>.azurerm_role_assignment.this["<principal_oid>"]`, run the following for
each principal before the next `terraform plan`:

```sh
terraform state mv \
  'module.<caller>.azurerm_role_assignment.this["<principal_oid>"]' \
  'module.<caller>.module.role_assignments["<principal_oid>"].azurerm_role_assignment.this'
```

Skip this step if the module was first deployed at the version that introduced the
`../RoleAssignment` composition (before the broken moved block existed).

## Outputs

| Name | Description |
|------|-------------|
| id | Container Registry ID |
| name | Container Registry name |
| login_server | Login server URL (e.g. crapiprodgwc001.azurecr.io) |
| private_endpoint_ids | Map of private endpoint key => Private Endpoint resource ID |
| private_endpoint_ip_addresses | Map of private endpoint key => assigned private IP address |
| resource | Complete Container Registry resource object |

## Private Endpoint

Attach one or more Private Endpoints to the registry (sub-resource `registry`, DNS zone `privatelink.azurecr.io`). **Requires the Premium SKU** (ACR Private Link is Premium-only) — enforced by a plan-time precondition. Delegated to the in-repo `PrivateEndpoint` module, one instance per entry (each may land in its own subnet).

```hcl
module "acr" {
  source = "../ContainerRegistry"
  # ...
  sku                           = "Premium"
  public_network_access_enabled = false

  private_endpoints = {
    primary = {
      subnet_id            = "/subscriptions/.../subnets/snet-pe"
      private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.azurecr.io"]
    }
  }
}
```

> **DNS / data endpoints**: with a private endpoint, ACR auto-enables dedicated data endpoints. Clients must also resolve `<registry>.<region>.data.azurecr.io` — the `privatelink.azurecr.io` zone covers both the registry and data A-records (or let an ALZ DINE policy wire DNS and omit `private_dns_zone_ids`).
