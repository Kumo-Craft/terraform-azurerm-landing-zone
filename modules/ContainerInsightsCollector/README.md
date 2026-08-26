# ContainerInsightsCollector

Creates an explicit Data Collection Rule (DCR) and DCR Association (DCRA) that route Container Insights streams from an AKS cluster to a Log Analytics Workspace. This module overrides the default DCR auto-created by the `oms_agent` addon, giving full control over stream selection, namespace filtering, and ContainerLogV2 settings. The override pattern is the modern Microsoft-recommended approach (Azure Monitor documentation, `kubernetes-monitoring-enable.md`, updated 2026-04-17).

## Prerequisites

- An AKS cluster with the `oms_agent` addon enabled (installs the ama-logs DaemonSet). This addon must be enabled separately — this module only deploys the DCR + DCRA, not the agent.
- A Log Analytics Workspace in the same subscription (or reachable cross-subscription).
- The caller must supply the LAW resource ID (`log_analytics_workspace_id`).

## Usage

### Standalone

```hcl
module "container_insights" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/ContainerInsightsCollector?ref=v0.2.84"

  subscription_acronym       = "api"
  environment                = "prod"
  region_code                = "gwc"
  location                   = "germanywestcentral"
  workload                   = "containerinsights"
  resource_group_name        = "rg-api-prod-gwc-aks"
  aks_cluster_id             = "/subscriptions/.../managedClusters/aks-api-prod-gwc-001"
  log_analytics_workspace_id = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01"

  lock = { kind = "CanNotDelete" }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ContainerInsightsCollector"
}

inputs = {
  subscription_acronym       = include.sub.locals.subscription_acronym
  environment                = include.root.inputs.environment
  region_code                = include.root.inputs.region_code
  location                   = include.root.inputs.location
  workload                   = "containerinsights"
  resource_group_name        = dependency.rg.outputs.name
  aks_cluster_id             = dependency.aks.outputs.id
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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Explicit DCR name override (escape hatch). If null, derived from naming convention. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. api, mgm). Required when `name` is null. | `string` | `null` | Conditional |
| environment | Environment (e.g. prod, nprd). Required when `name` is null. | `string` | `null` | Conditional |
| region_code | Region code (e.g. gwc, weu). Required when `name` is null. | `string` | `null` | Conditional |
| workload | Workload suffix in the DCR/DCRA names. | `string` | `"containerinsights"` | No |
| location | Azure region for the DCR (must match the AKS cluster's region). | `string` | -- | Yes |
| resource_group_name | Resource group where the DCR is deployed. | `string` | -- | Yes |
| aks_cluster_id | Full resource ID of the AKS cluster to associate the DCR with. | `string` | -- | Yes |
| log_analytics_workspace_id | Full resource ID of the Log Analytics Workspace. | `string` | -- | Yes |
| streams | List of Container Insights streams to collect. | `list(string)` | See below | No |
| data_collection_settings | Container Insights agent settings (interval, namespace filter, ContainerLogV2). | `object` | `{}` | No |
| lock | Optional resource lock (`CanNotDelete` / `ReadOnly`). Null to skip. | `object` | `null` | No |
| role_assignments | Map of role assignments on the DCR. | `map(object)` | `{}` | No |
| tags | Tags applied to the DCR. | `map(string)` | `{}` | No |

### Default streams

The default stream list opts into ContainerLogV2 and skips two streams present in addon defaults:

- **Excluded: `Microsoft-ContainerLog`** — V1, deprecated. Use `Microsoft-ContainerLogV2` instead.
- **Excluded: `Microsoft-Perf`** — redundant when Managed Prometheus is enabled on the same cluster.

Default list: `Microsoft-ContainerLogV2`, `Microsoft-KubeEvents`, `Microsoft-KubePodInventory`, `Microsoft-KubeNodeInventory`, `Microsoft-KubeServices`, `Microsoft-KubePVInventory`, `Microsoft-KubeMonAgentEvents`, `Microsoft-ContainerNodeInventory`, `Microsoft-ContainerInventory`, `Microsoft-InsightsMetrics`.

## Outputs

| Name | Description |
|------|-------------|
| id | DCR resource ID (alias for dcr_id, sibling convention). |
| dcr_id | Resource ID of the Container Insights DCR. |
| dcr_name | Name of the Container Insights DCR. |
| dcra_id | Resource ID of the DCR association on the AKS cluster. |
| resource | The complete `azurerm_monitor_data_collection_rule` resource object. |
| lock_id | Resource lock ID when `var.lock` is set, otherwise null. |
| role_assignment_ids | Map of role assignment IDs keyed by `var.role_assignments` map key. |

## Resources

| Name | Type |
|------|------|
| azurerm_monitor_data_collection_rule.ci | resource |
| azurerm_monitor_data_collection_rule_association.ci | resource |
| module.naming (conditional) | module |
| module.lock | module |
| module.role_assignments (for_each) | module |
| time_static.time | resource |

## Notes on Container Insights best practices

- **ContainerLogV2 is the preferred log schema** as of Azure Monitor Container Insights v2. It reduces ingestion cost and adds structured fields (pod name, namespace, container name) compared to the deprecated V1 schema.
- **Omit `Microsoft-Perf` when Managed Prometheus is enabled.** Both streams carry node/pod metrics; collecting both doubles cost without adding value. This module excludes Perf by default.
- **Namespace filtering** is available via `data_collection_settings.namespace_filter_mode` (`Off` / `Include` / `Exclude`) together with `data_collection_settings.namespaces`. Use `Include` to restrict collection to specific workload namespaces and reduce LAW ingestion volume.
- **The oms_agent addon must be enabled on the cluster separately.** This module provisions only the DCR and DCRA; it does not enable the addon or install the ama-logs DaemonSet.

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_data_collection_rule.ci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_data_collection_rule_association.ci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aks\_cluster\_id | Full resource ID of the AKS cluster to associate the DCR with. | `string` | n/a | yes |
| location | Azure region for the DCR (must match the AKS cluster's region). | `string` | n/a | yes |
| log\_analytics\_workspace\_id | Full resource ID of the Log Analytics Workspace receiving Container Insights data. | `string` | n/a | yes |
| resource\_group\_name | Resource group where the DCR is deployed (typically the AKS cluster RG). | `string` | n/a | yes |
| data\_collection\_settings | Container Insights agent settings (passed as extension\_json to the<br>ContainerInsights data source extension).<br><br>- interval: scrape interval, ISO 8601-ish (e.g. "1m", "30s").<br>- namespace\_filter\_mode: "Off" (collect all), "Include", or "Exclude".<br>- namespaces: list of k8s namespaces matching the filter mode.<br>- enable\_container\_log\_v2: emit ContainerLogV2 (modern) when true. | <pre>object({<br>    interval                = optional(string, "1m")<br>    namespace_filter_mode   = optional(string, "Off")<br>    namespaces              = optional(list(string), [])<br>    enable_container_log_v2 = optional(bool, true)<br>  })</pre> | `{}` | no |
| environment | Environment (e.g. prod, nprd). | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the DCR. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit DCR name override (escape hatch). If null, derived from naming convention via ../Naming. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu). | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this DCR. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal to assign the role to.<br>- `principal_type`                         - (Optional) User, Group, or ServicePrincipal.<br>- `condition`                              - (Optional) ABAC condition.<br>- `condition_version`                      - (Optional) Condition version ("2.0").<br>- `description`                            - (Optional) Description.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check.<br>- `delegated_managed_identity_resource_id` - (Optional) Cross-tenant. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string, "ServicePrincipal")<br>    condition                              = optional(string, null)<br>    condition_version                      = optional(string, null)<br>    description                            = optional(string, null)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string, null)<br>  }))</pre> | `{}` | no |
| streams | Streams to collect. Defaults to the modern Container Insights set<br>(ContainerLogV2 for stdout/stderr, KubeEvents, KubePodInventory,<br>KubeNodeInventory, KubeServices, KubePVInventory, KubeMonAgentEvents,<br>ContainerNodeInventory, ContainerInventory, InsightsMetrics).<br><br>Skipped on purpose vs the addon defaults:<br>  - Microsoft-ContainerLog (V1, deprecated — use V2)<br>  - Microsoft-Perf (redundant with Managed Prometheus) | `list(string)` | <pre>[<br>  "Microsoft-ContainerLogV2",<br>  "Microsoft-KubeEvents",<br>  "Microsoft-KubePodInventory",<br>  "Microsoft-KubeNodeInventory",<br>  "Microsoft-KubeServices",<br>  "Microsoft-KubePVInventory",<br>  "Microsoft-KubeMonAgentEvents",<br>  "Microsoft-ContainerNodeInventory",<br>  "Microsoft-ContainerInventory",<br>  "Microsoft-InsightsMetrics"<br>]</pre> | no |
| subscription\_acronym | Subscription acronym (e.g. shc, api, mgm). | `string` | `null` | no |
| tags | Tags applied to the DCR. | `map(string)` | `{}` | no |
| workload | Workload suffix in the DCR/DCRA names. | `string` | `"containerinsights"` | no |

## Outputs

| Name | Description |
|------|-------------|
| dcr\_id | Resource ID of the Container Insights Data Collection Rule. |
| dcr\_name | Name of the Container Insights Data Collection Rule. |
| dcra\_id | Resource ID of the DCR association on the AKS cluster. |
| id | DCR resource ID (alias for dcr\_id, sibling convention). |
| lock\_id | Resource lock ID when var.lock is set, otherwise null. |
| resource | The azurerm\_monitor\_data\_collection\_rule resource (DCR routing Container Insights streams). |
| role\_assignment\_ids | Map of role assignment IDs keyed by the var.role\_assignments map key. |
<!-- END_TF_DOCS -->
