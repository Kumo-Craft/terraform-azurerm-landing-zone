# FlowLogs

Deploys **Azure VNet Flow Logs** with optional Traffic Analytics on one or more virtual networks. Uses `azurerm_network_watcher_flow_log` targeting VNets directly — the modern API. NSG flow logs are deprecated and reach end-of-life on **2027-09-30**.

One `azurerm_network_watcher_flow_log` resource is created per entry in `var.vnets`. Naming follows the house convention `fl-{acr}-{env}-{region}-{workload}-{vnet_key}` (inline slug — `network_watcher_flow_log` is not a key in `Azure/naming/azurerm 0.4.3`). Per-entry `name` overrides the computed name.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Usage

### Standalone

```hcl
module "flow_logs" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/FlowLogs?ref=v0.2.56"

  subscription_acronym = "con"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "network"
  location             = "germanywestcentral"

  network_watcher_name                = "NetworkWatcher_germanywestcentral"
  network_watcher_resource_group_name = "NetworkWatcherRG"
  storage_account_id                  = "/subscriptions/.../storageAccounts/stconnprdgwcflowlogs"

  retention_days = 90

  traffic_analytics = {
    workspace_id          = "82f9d847-335e-4441-adee-38a48dd8a613"
    workspace_region      = "germanywestcentral"
    workspace_resource_id = "/subscriptions/.../workspaces/law-mgm-nprd-gwc-core"
    interval_minutes      = 60
  }

  vnets = {
    nva = {
      id      = "/subscriptions/.../virtualNetworks/vnet-con-nprd-gwc-nva"
      enabled = true
      lock    = { kind = "CanNotDelete" }
      role_assignments = {
        reader = {
          role_definition_id_or_name = "Reader"
          principal_id               = "00000000-0000-0000-0000-000000000001"
          principal_type             = "Group"
        }
      }
    }
    shared = {
      id      = "/subscriptions/.../virtualNetworks/vnet-con-nprd-gwc-shared"
      enabled = true
      # explicit name override — skips computed convention
      name = "fl-con-nprd-gwc-shared-custom"
    }
  }

  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/FlowLogs"
}

dependency "nw"      { config_path = "../network-watcher" }
dependency "vnet_nva"    { config_path = "../network-nva" }
dependency "vnet_shared" { config_path = "../network-shared" }
dependency "storage" { config_path = "../st-flowlogs" }
dependency "law"     { config_path = "${get_repo_root()}/landing-zone/platform/management/alz-management" }

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "network"
  location             = include.root.inputs.location

  network_watcher_name                = dependency.nw.outputs.name
  network_watcher_resource_group_name = dependency.nw.outputs.resource_group_name
  storage_account_id                  = dependency.storage.outputs.id

  traffic_analytics = {
    workspace_id          = dependency.law.outputs.law_workspace_id
    workspace_region      = include.root.inputs.location
    workspace_resource_id = dependency.law.outputs.law_id
    interval_minutes      = 60
  }

  vnets = {
    nva    = { id = dependency.vnet_nva.outputs.id }
    shared = { id = dependency.vnet_shared.outputs.id }
  }

  tags = include.root.inputs.common_tags
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `subscription_acronym` | `string` | `null` | conditional | Subscription acronym (2-5 lowercase letters). Required when `workload` is set. |
| `environment` | `string` | `null` | conditional | Environment code (2-4 lowercase letters). Required when `workload` is set. |
| `region_code` | `string` | `null` | conditional | Region code (2-5 lowercase letters). Required when `workload` is set. |
| `workload` | `string` | `null` | conditional | Workload component. Required unless every `vnets` entry provides an explicit `name`. |
| `location` | `string` | — | yes | Azure region for flow log resources. |
| `network_watcher_name` | `string` | — | yes | Name of the existing Network Watcher. |
| `network_watcher_resource_group_name` | `string` | — | yes | Resource group containing the Network Watcher. |
| `storage_account_id` | `string` | — | yes | Storage Account resource ID for raw flow log data. |
| `vnets` | `map(object)` | — | yes | Map of VNets to enable flow logs on. Key is used as the per-entry disambiguator in the resource name. See schema below. |
| `retention_days` | `number` | `90` | no | Days to retain flow logs (0 = forever / SA lifecycle policy). |
| `traffic_analytics` | `object` | `null` | no | Traffic Analytics configuration. `null` disables it. |
| `tags` | `map(string)` | `{}` | no | Tags applied to all resources. |

### `vnets` entry schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `string` | required | VNet resource ID. |
| `enabled` | `bool` | `true` | Enable/disable this flow log. |
| `name` | `string` | `null` | Explicit resource name override. Computed when null. |
| `lock` | `object({kind, name?})` | `null` | Management lock. `kind` must be `CanNotDelete` or `ReadOnly`. |
| `role_assignments` | `map(object)` | `{}` | Role assignments scoped to this flow log. |

### `traffic_analytics` schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `true` | Enable Traffic Analytics. |
| `workspace_id` | `string` | required | Log Analytics Workspace GUID. |
| `workspace_region` | `string` | required | Region of the workspace. |
| `workspace_resource_id` | `string` | required | ARM resource ID of the workspace. |
| `interval_minutes` | `number` | `60` | Aggregation interval. Must be `10` or `60`. |

## Outputs

| Name | Description |
|------|-------------|
| `ids` | Map of VNet key to flow log resource ID. |
| `names` | Map of VNet key to flow log resource name. |
| `lock_ids` | Map of VNet key to management lock resource ID (entries with a lock only). |
| `role_assignment_ids` | Map of `<vnet_key>.<assignment_key>` to role assignment resource ID. |
| `resources` | Map of vnet_key to curated flow log attributes (id, name, location, resource_group_name, network_watcher_name, target_resource_id, storage_account_id, enabled, version, retention_policy, traffic_analytics, tags). Explicit list on purpose — omits the provider-deprecated `network_security_group_id` that a raw resource-object output would surface. |

## Notes

- **VNet flow logs (not NSG flow logs)**: this module uses `azurerm_network_watcher_flow_log` targeting VNets. NSG flow logs are deprecated and end-of-life on **2027-09-30**.
- **`retention_days = 0`**: disables the built-in retention policy (days = 0, enabled = false). Azure does **not** delete existing blobs; flow log data persists until the Storage Account lifecycle management policy removes it (effectively infinite if no lifecycle policy is configured). Set a positive value for an explicit day-based cutoff.

  Note: Most callers expecting "no retention / clean up immediately" should instead configure a lifecycle management policy on the Storage Account rather than relying on `retention_days = 0`.
- **Storage account constraints**: Microsoft Flow Logs service requires shared-key auth and writes from Microsoft-managed infrastructure. The MCSB shared-key / VNet-rule / Private-Link checks on this storage account are by-design exempted.
- **Traffic Analytics**: requires both the workspace GUID (`workspace_id`) and the ARM resource ID (`workspace_resource_id`). Both are available from the LAW module outputs.

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
| [azurerm_network_watcher_flow_log.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_watcher_flow_log) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| network\_watcher\_name | Name of the Network Watcher to host the flow log resources | `string` | n/a | yes |
| network\_watcher\_resource\_group\_name | Resource group of the Network Watcher | `string` | n/a | yes |
| storage\_account\_id | Storage Account resource ID for flow log data | `string` | n/a | yes |
| vnets | Map of VNets to enable flow logs on. Key = short name used in the flow log resource name. | <pre>map(object({<br>    id      = string<br>    enabled = optional(bool, true)<br>    # F-3: per-entry name override<br>    name = optional(string)<br>    # F-5: per-entry lock<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br>    # F-6: per-entry role assignments<br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name       = string<br>      principal_id                     = string<br>      principal_type                   = optional(string, "ServicePrincipal")<br>      condition                        = optional(string)<br>      condition_version                = optional(string)<br>      description                      = optional(string)<br>      skip_service_principal_aad_check = optional(bool, false)<br>    })), {})<br>  }))</pre> | n/a | yes |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| retention\_days | Number of days to retain flow logs in the storage account (0 = forever / SA lifecycle policy) | `number` | `90` | no |
| subscription\_acronym | Subscription acronym (e.g. con, mgm, api) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| traffic\_analytics | Traffic Analytics configuration. Set to null to disable. | <pre>object({<br>    enabled               = optional(bool, true)<br>    workspace_id          = string<br>    workspace_region      = string<br>    workspace_resource_id = string<br>    interval_minutes      = optional(number, 60)<br>  })</pre> | `null` | no |
| workload | Workload component for naming convention fl-{acr}-{env}-{region}-{workload}-{vnet\_key}. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of VNet key to flow log resource ID |
| lock\_ids | Map of VNet key to management lock resource ID (only entries that have a lock configured) |
| names | Map of VNet key to flow log resource name |
| resources | Map of vnet\_key => curated flow log attributes. Explicit field list on purpose: exposing the raw resource object surfaced the provider-deprecated network\_security\_group\_id attribute (legacy NSG-attached model) and emitted a 'Deprecated value used' warning even though this module uses the VNet model via target\_resource\_id. |
| role\_assignment\_ids | Map of '<vnet\_key>.<assignment\_key>' to role assignment resource ID |
<!-- END_TF_DOCS -->
