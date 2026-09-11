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
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/ContainerInsightsCollector?ref=v0.2.84"

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
