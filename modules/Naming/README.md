# Naming

Thin wrapper around [`Azure/naming/azurerm`](https://registry.terraform.io/modules/Azure/naming/azurerm/0.4.3) (pinned `v0.4.3`) that composes the house naming convention from the four standard segments — `subscription_acronym`, `environment`, `region_code`, `workload` — and exposes every per-type name produced by the upstream module.

Use it as a building block in any module that needs to name an Azure resource. The upstream module owns the per-type prefix (`kv-`, `cr`, `st`, …), the character set rules, and the length caps; this wrapper owns the house convention.

## Convention

```
{type_prefix}-{subscription_acronym}-{environment}-{region_code}-{workload}
```

| Resource type             | Key                        | Example output                                                   | Quirks                                                                                             |
| ------------------------- | -------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Resource Group            | `resource_group`           | `rg-shc-nprd-gwc-platform`                                       |                                                                                                    |
| Virtual Network           | `virtual_network`          | `vnet-shc-nprd-gwc-platform`                                     |                                                                                                    |
| Subnet                    | `subnet`                   | `snet-shc-nprd-gwc-platform`                                     |                                                                                                    |
| Network Interface         | `network_interface`        | `nic-shc-nprd-gwc-platform`                                      |                                                                                                    |
| Virtual Machine           | `virtual_machine`          | `vm-shc-nprd-gwc-pl` (suffix truncated)                          | **15-char cap** (Windows NetBIOS). Use `var.name` override when suffix exceeds 15 chars.           |
| AKS cluster               | `kubernetes_cluster`       | `aks-shc-nprd-gwc-platform`                                      |                                                                                                    |
| Key Vault                 | `key_vault`                | `kv-shc-nprd-gwc-platform` (capped at 24)                        |                                                                                                    |
| Key Vault Certificate     | `key_vault_certificate`    | `kv-cert-shc-nprd-gwc-platform`                                  | **Present but often missed** — use `result.key_vault_certificate.name`, not an inline `cert-` slug |
| Storage Account           | `storage_account`          | `stshcnprdgwcplatform` (no hyphens, ≤ 24)                        | Lowercase alphanumerics only, hyphens stripped                                                     |
| Container Registry        | `container_registry`       | `crshcnprdgwcplatform` (no hyphens)                              | Lowercase alphanumerics only, hyphens stripped                                                     |
| Network Security Group    | `network_security_group`   | `nsg-shc-nprd-gwc-platform`                                      |                                                                                                    |
| Route Table               | `route_table`              | `rt-shc-nprd-gwc-platform`                                       |                                                                                                    |
| NAT Gateway               | `nat_gateway`              | `ng-shc-nprd-gwc-platform`                                       |                                                                                                    |
| Log Analytics Workspace   | `log_analytics_workspace`  | `log-shc-nprd-gwc-platform`                                      |                                                                                                    |

For the exhaustive list of 300+ keys, see the upstream registry: `https://registry.terraform.io/modules/Azure/naming/azurerm/0.4.3`.

## Usage

In-repo callers use the relative path shown below. External consumers must pin to a semver tag. Never use `?ref=main` — it is a floating pin that silently pulls breaking changes.

```hcl
# External consumers (Terragrunt / standalone)
source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/Naming?ref=v0.2.89"
```

### Standalone (inside another module)

```hcl
module "naming" {
  source = "../Naming"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

resource "azurerm_key_vault" "this" {
  name                = module.naming.result.key_vault.name
  resource_group_name = var.resource_group_name
  location            = var.location
  # ...
}
```

### With an instance index (`extra_suffix`)

```hcl
module "naming" {
  source = "../Naming"

  subscription_acronym = "shc"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "platform"
  extra_suffix         = ["01"]
}

# module.naming.result.resource_group.name == "rg-shc-nprd-gwc-platform-01"
```

### Random unique segment (collision-safe)

By default the wrapper produces deterministic names (`unique_length = 0`). To append a stable random segment, set `unique_length > 0` — the seed defaults to the joined suffix, so the random segment stays the same across applies for identical inputs.

```hcl
module "naming" {
  source = "../Naming"

  subscription_acronym = "shc"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "platform"
  unique_length        = 4
}

# module.naming.result.storage_account.name_unique == "stshcnprdgwcplatformx1y2"
```

## Known quirks

### `var.environment` and `var.region_code` validation regex

`var.environment` is validated against `^[a-z]{2,4}$` — **2 to 4 lowercase letters only**. Values longer than 4 characters (e.g. `sandbox`, `staging`) are rejected at plan time with the message `environment must be 2 to 4 lowercase letters.`

`var.region_code` is validated against `^[a-z]{2,5}$` — **2 to 5 lowercase letters only**. Any digit or uppercase character (e.g. `GWC1`, `Weu`) is rejected at plan time with the message `region_code must be 2 to 5 lowercase letters.`

Canonical values in use across this repo:

| Variable | Accepted examples |
|---|---|
| `environment` | `prod`, `nprd`, `dev`, `tst`, `acc`, `qa`, `uat`, `stg` (max 4 chars) |
| `region_code` | `gwc`, `weu`, `neu`, `eus`, `wus` (2-5 lowercase letters) |

If a new environment label longer than 4 characters is introduced (e.g. `sandbox`), the regex in `variables.tf:34` must be widened before that value can be used across any of the 50+ modules that consume Naming.

### Truncation behavior — `virtual_machine.name` capped at 15 characters

The upstream `Azure/naming/azurerm` module enforces the Windows NetBIOS 15-character limit on `virtual_machine.name`. Any suffix that produces a name longer than 15 chars will be silently truncated at the workload segment.

Example: inputs `["api", "prod", "gwc", "app"]` produce `"vm-api-prod-gwc"` — the `app` workload is silently dropped.

Recommendation: use the `var.name` escape hatch in caller modules when a full 4-segment suffix would exceed 15 chars.

```hcl
module "naming" {
  source = "../Naming"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "app"
  # result.virtual_machine.name may be truncated — verify length or use var.name override
}
```

### Absent keys — require inline-slug fallback

The following Azure resource types are **not present** in `Azure/naming/azurerm` v0.4.3. Caller modules must use an inline slug instead of `result.<key>.name`:

| Resource                       | Inline slug | Example pattern                                              | Canonical usage                     |
| ------------------------------ | ----------- | ------------------------------------------------------------ | ----------------------------------- |
| `monitor_private_link_scope`   | `pls-`      | `"pls-${join("-", module.naming["this"].suffix)}"`           | Ampls v0.2.63                       |
| `network_watcher_flow_log`     | `fl-`       | `"fl-${join("-", module.naming["this"].suffix)}"`            | FlowLogs v0.2.56                    |
| `private_dns_resolver`         | `dnspr-`    | `"dnspr-${join("-", module.naming["this"].suffix)}"`         | DnsResolver v0.2.55                 |

### Present keys often missed — do NOT use an inline slug

| Resource                    | Key                         | Note                                                                                                                        |
| --------------------------- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Key Vault Certificate       | `key_vault_certificate`     | IS PRESENT in v0.4.3. Use `result.key_vault_certificate.name`. The `cert-` inline slug used in TlsSelfSignedCert v0.2.64 is preserved for backward-compat but new callers must use the upstream key. |

### How to discover all available keys

The upstream module exposes 300+ resource type keys. Browse the full list at:
`https://registry.terraform.io/modules/Azure/naming/azurerm/0.4.3`

## Inputs

| Name                     | Type           | Default | Description                                                                                              |
| ------------------------ | -------------- | ------- | -------------------------------------------------------------------------------------------------------- |
| `subscription_acronym`   | `string`       | —       | 2-5 lowercase letters. Subscription identifier (e.g. `mgm`, `con`, `shc`).                               |
| `environment`            | `string`       | —       | 2-4 lowercase letters (e.g. `prod`, `nprd`).                                                             |
| `region_code`            | `string`       | —       | 2-5 lowercase letters (e.g. `gwc`, `weu`).                                                               |
| `workload`               | `string`       | —       | 2-31 chars, lowercase + digits + hyphens (must start alphanumeric).                                      |
| `prefix`                 | `list(string)` | `[]`    | Segments prepended BEFORE the upstream type prefix. Azure recommends suffixing — leave empty by default. |
| `extra_suffix`           | `list(string)` | `[]`    | Segments appended AFTER `workload`. Use for instance indices, sub-component qualifiers, …                |
| `unique_length`          | `number`       | `0`     | Length of the random unique segment (0-60). `0` keeps names deterministic.                               |
| `unique_seed`            | `string`       | `null`  | Seed for the random segment. When null, defaults to the joined suffix.                                   |
| `unique_include_numbers` | `bool`         | `true`  | Allow digits in the random segment. Only relevant when `unique_length > 0`.                              |

## Outputs

| Name          | Description                                                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `result`      | All per-resource-type naming outputs from `Azure/naming/azurerm`. Access via `result.<type>.name` (e.g. `result.key_vault.name`).             |
| `suffix`      | The composed suffix list passed to the upstream module.                                                                                       |
| `unique_seed` | The effective seed used for the random segment (input override, or joined suffix when null).                                                  |

Each `result.<type>` object exposes `.name`, `.name_unique`, `.dashes`, `.slug`, `.min_length`, `.max_length`, `.scope`, and `.regex` — refer to the upstream module documentation for the full surface.

## Tests

```bash
cd Naming
terraform init -backend=false
terraform test
```

Plan-time only, no Azure credentials or mocks required (the module creates no `azurerm` resources).

## Upstream

- Module: [`Azure/naming/azurerm`](https://registry.terraform.io/modules/Azure/naming/azurerm/0.4.3) v0.4.3
- Source: <https://github.com/Azure/terraform-azurerm-naming>
