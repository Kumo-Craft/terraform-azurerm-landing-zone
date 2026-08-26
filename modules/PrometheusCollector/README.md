# PrometheusCollector

Creates a Prometheus-forwarder Data Collection Rule (DCR) and associates it with an AKS cluster to forward metrics to an Azure Monitor Workspace. Optionally deploys recommended Kubernetes and Node recording rule groups.

## Usage

### Standalone

```hcl
module "prometheus_collector" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PrometheusCollector?ref=v0.2.42"

  subscription_acronym        = "api"
  environment                 = "prod"
  region_code                 = "gwc"
  location                    = "germanywestcentral"
  workload                    = "prometheus"
  resource_group_name         = "rg-api-prod-gwc-aks"
  aks_cluster_id              = "/subscriptions/.../managedClusters/aks-api-prod-gwc-001"
  aks_cluster_name            = "aks-api-prod-gwc-001"
  monitor_workspace_id        = "/subscriptions/.../accounts/amw-mgm-prod-gwc-01"
  data_collection_endpoint_id = "/subscriptions/.../dataCollectionEndpoints/dce-mgm-prod-gwc-01"

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PrometheusCollector"
}

inputs = {
  subscription_acronym        = include.sub.locals.subscription_acronym
  environment                 = include.root.inputs.environment
  region_code                 = include.root.inputs.region_code
  location                    = include.root.inputs.location
  workload                    = "prometheus"
  resource_group_name         = dependency.rg.outputs.name
  aks_cluster_id              = dependency.aks.outputs.id
  aks_cluster_name            = dependency.aks.outputs.name
  monitor_workspace_id        = dependency.amw.outputs.id
  data_collection_endpoint_id = dependency.amw.outputs.default_data_collection_endpoint_id
  tags                        = include.root.inputs.common_tags
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
| location | Azure region | `string` | -- | Yes |
| workload | Workload suffix for the DCR name | `string` | `"prometheus"` | No |
| resource_group_name | Resource group for the Data Collection Rule | `string` | -- | Yes |
| aks_cluster_id | AKS cluster ID to collect Prometheus metrics from | `string` | -- | Yes |
| aks_cluster_name | AKS cluster name (for recording rule group scope) | `string` | -- | Yes |
| enable_recording_rules | Enable recommended Prometheus recording rules | `bool` | `true` | No |
| monitor_workspace_id | Azure Monitor Workspace ID (Prometheus destination) | `string` | -- | Yes |
| data_collection_endpoint_id | Data Collection Endpoint ID | `string` | -- | Yes |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| dcr_id | The ID of the Data Collection Rule |
| dcr_name | The name of the Data Collection Rule |
| resource | Complete Data Collection Rule resource object |
