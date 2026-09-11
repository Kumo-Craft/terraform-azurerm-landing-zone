# AzureMonitorWorkspace

Creates an Azure Monitor Workspace (managed Prometheus metrics store) with an optional Private Endpoint for the `prometheusMetrics` subresource.

## Usage

### Standalone

```hcl
module "azure_monitor_workspace" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AzureMonitorWorkspace?ref=v0.2.41"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-monitor"

  public_network_access_enabled = false
  subnet_id                     = "/subscriptions/.../subnets/snet-mgm-prod-gwc-pe"

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AzureMonitorWorkspace"
}

inputs = {
  subscription_acronym          = include.sub.locals.subscription_acronym
  environment                   = include.root.inputs.environment
  region_code                   = include.root.inputs.region_code
  workload                      = "01"
  location                      = include.root.inputs.location
  resource_group_name           = dependency.rg.outputs.name
  public_network_access_enabled = false
  subnet_id                     = dependency.subnet.outputs.subnet_ids["snet-mgm-prod-gwc-pe"]
  tags                          = include.root.inputs.common_tags
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
| name | Optional. Explicit name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload suffix | `string` | `"01"` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| public_network_access_enabled | Whether public network access is enabled | `bool` | `false` | No |
| subnet_id | Subnet ID for the Private Endpoint. If null, no PE is created. | `string` | `null` | No |
| private_dns_zone_ids | Optional. Private DNS zone IDs to bind to the PE via a `private_dns_zone_group`. For Managed Prometheus the zone is regional: `privatelink.<region>.prometheus.monitor.azure.com`. Empty (default) = zone group left to the ALZ DINE policy. | `list(string)` | `[]` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Private DNS zone group (DINE vs explicit)

By default (`private_dns_zone_ids = []`) the PE's `private_dns_zone_group` is left to the ALZ **DINE** initiative *Deploy-Private-DNS-Zones*, and TF ignores changes to it (`lifecycle.ignore_changes`).

However, the DINE initiative does **not** currently cover the Managed Prometheus regional zone `privatelink.<region>.prometheus.monitor.azure.com`. On subs where that zone is not auto-linked, the PE's zone group stays empty and private resolution of the AMW endpoint fails (`no such host`). Set `private_dns_zone_ids` to manage the zone group explicitly in Terraform:

```hcl
private_dns_zone_ids = [
  "/subscriptions/.../resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.germanywestcentral.prometheus.monitor.azure.com"
]
```

⚠️ **`ignore_changes` nuance** — the `lifecycle.ignore_changes = [private_dns_zone_group]` is kept for DINE back-compat. Consequence:
- On a **new** AMW, the zone group is posted at creation time.
- On an **already existing** PE, newly setting `private_dns_zone_ids` will **not** apply on a plain `terraform apply` (the update diff is ignored). Force a PE recreation:
  ```
  terraform apply -replace='module.<name>.azurerm_private_endpoint.this[0]'
  ```
  This is non-destructive for the AMW itself (it has `prevent_destroy = true`).

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Monitor Workspace |
| name | The name of the Azure Monitor Workspace |
| query_endpoint | The query endpoint for the Azure Monitor Workspace |
| default_data_collection_endpoint_id | The default Data Collection Endpoint ID |
| default_data_collection_rule_id | The default Data Collection Rule ID |
| resource | Complete Azure Monitor Workspace resource object |
| private_endpoint_id | The ID of the Private Endpoint (null if no PE) |
| private_endpoint_ip | The private IP address of the Private Endpoint |
