# FinOpsHub

Deploys the Microsoft FinOps Toolkit Hub infrastructure: ADLS Gen2 storage account with msexports/ingestion/config containers, Azure Data Explorer cluster, Data Factory with ETL pipeline, Event Grid for blob notifications, and RBAC assignments. The caller provides the resource group — compose with `../ResourceGroup` at root.

## Breaking changes (v0.2.49)

### F-1 — Inline ResourceGroup removed

The module no longer creates the resource group internally. You must create it at the caller root and pass the name via the new required input `resource_group_name`.

**Migration recipe**

1. Move RG creation to caller root using `../ResourceGroup`.
2. Run the state move before the next apply:
   ```
   terraform state mv module.finops_hub.azurerm_resource_group.this \
     module.resource_group.azurerm_resource_group.this["finops"]
   ```
3. Add the new required input to your module call:
   ```hcl
   resource_group_name = module.resource_group.names["finops"]
   ```
4. Remove any downstream references to the old outputs `resource_group_name` and `resource_group_id` (no longer emitted by this module).

If the state mv is skipped, the `removed { lifecycle.destroy = false }` tombstone block in `main.tf` prevents Terraform from trying to destroy the Azure RG.

Canonical RG-drop precedents: Grafana v0.2.46, NetworkStack v0.2.8, PaloCluster v0.2.25, PrivateDnsZones v0.2.9.

## Usage

### Standalone

```hcl
module "finops_hub" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/FinOpsHub?ref=v0.2.49"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = module.resource_group.names["finops"]

  storage_replication_type   = "LRS"
  export_retention_days      = 30
  ingestion_retention_months = 13

  enable_data_explorer = true
  adx_sku_name         = "Dev(No SLA)_Standard_D11_v2"
  adx_sku_capacity     = 1

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/FinOpsHub"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  location             = include.root.inputs.location
  resource_group_name  = dependency.resource_group.outputs.names["finops"]
  tags                 = include.root.inputs.common_tags
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
| resource_group_name | Name of the resource group (caller-provided) | `string` | -- | Yes |
| subscription_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | No* |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No* |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No* |
| workload | Workload identifier | `string` | `"finops"` | No |
| name | Explicit name override (escape hatch) | `string` | `null` | No* |
| location | Azure region | `string` | -- | Yes |
| tags | Tags to apply to all resources | `map(string)` | `{}` | No |
| storage_replication_type | Replication type for the storage account (LRS, ZRS) | `string` | `"LRS"` | No |
| export_retention_days | Days to retain raw exports in msexports container (0 = delete after processing) | `number` | `0` | No |
| ingestion_retention_months | Months to retain ingested data in ingestion container | `number` | `13` | No |
| enable_data_explorer | Deploy Azure Data Explorer cluster and databases | `bool` | `true` | No |
| adx_sku_name | ADX cluster SKU name | `string` | `"Dev(No SLA)_Standard_D11_v2"` | No |
| adx_sku_capacity | ADX cluster node count (1 for dev, 2+ for prod) | `number` | `1` | No |
| adx_hot_cache_days | Days for ADX hot cache | `number` | `31` | No |
| adx_soft_delete_days | Days for ADX soft delete retention | `number` | `365` | No |
| adx_zones | Availability zones for ADX cluster (null = env-driven default) | `list(string)` | `null` | No |
| cost_management_exports_principal_id | Principal ID of the Azure Cost Management Exports Service Principal (null = no role assignment) | `string` | `null` | No |
| enable_public_access | Enable public network access on storage and ADF | `bool` | `false` | No |

\* Either `var.name` OR all four naming components (`subscription_acronym`, `environment`, `region_code`, `workload`) must be provided. See XOR validator on `var.name`.

## Outputs

| Name | Description |
|------|-------------|
| resource | The FinOps Hub storage account object (primary resource) |
| storage_account_id | The ID of the FinOps Hub storage account |
| storage_account_name | The name of the FinOps Hub storage account |
| adx_cluster_id | The ID of the ADX cluster |
| adx_cluster_uri | The URI of the ADX cluster |
| adx_cluster_name | The name of the ADX cluster |
| data_factory_id | The ID of the Data Factory |
| data_factory_name | The name of the Data Factory |
| data_factory_principal_id | The principal ID of the Data Factory managed identity |
| eventhub_namespace_id | The ID of the Event Hub Namespace |
| adx_ingestion_uri | The data ingestion URI of the ADX cluster |

## Known Limitations / Deferrals

- **ADF Managed Virtual Network** is DISABLED (`managed_virtual_network_enabled = false`). Enabling this requires Azure Private Endpoint support and approved integration runtimes routed through PE. Callers cannot opt-in without modifying module code.
- **Palo Alto Networks integration** is NOT included in this module — must be wired externally if required.
