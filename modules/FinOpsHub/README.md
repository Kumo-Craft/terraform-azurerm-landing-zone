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
| adf\_storage\_blob | ../RoleAssignment | n/a |
| adf\_storage\_reader | ../RoleAssignment | n/a |
| adx\_eventhub\_receiver | ../RoleAssignment | n/a |
| adx\_storage\_blob | ../RoleAssignment | n/a |
| cost\_mgmt\_exports\_storage | ../RoleAssignment | n/a |
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_data_factory.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory) | resource |
| [azurerm_data_factory_dataset_parquet.ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_dataset_parquet) | resource |
| [azurerm_data_factory_dataset_parquet.msexports](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_dataset_parquet) | resource |
| [azurerm_data_factory_linked_service_data_lake_storage_gen2.storage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_linked_service_data_lake_storage_gen2) | resource |
| [azurerm_data_factory_pipeline.msexports_etl](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_pipeline) | resource |
| [azurerm_data_factory_trigger_blob_event.msexports](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_trigger_blob_event) | resource |
| [azurerm_eventgrid_event_subscription.ingestion_to_eventhub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventgrid_event_subscription) | resource |
| [azurerm_eventgrid_system_topic.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventgrid_system_topic) | resource |
| [azurerm_eventhub.costs_ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub) | resource |
| [azurerm_eventhub_namespace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventhub_namespace) | resource |
| [azurerm_kusto_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_cluster) | resource |
| [azurerm_kusto_database.hub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_database) | resource |
| [azurerm_kusto_database.ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_database) | resource |
| [azurerm_kusto_database_principal_assignment.adf_hub_viewer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_database_principal_assignment) | resource |
| [azurerm_kusto_database_principal_assignment.adf_ingestion](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_database_principal_assignment) | resource |
| [azurerm_kusto_database_principal_assignment.hub_additional_viewers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_database_principal_assignment) | resource |
| [azurerm_kusto_database_principal_assignment.ingestion_additional_viewers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_database_principal_assignment) | resource |
| [azurerm_kusto_eventgrid_data_connection.costs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_eventgrid_data_connection) | resource |
| [azurerm_kusto_script.hub_setup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_script) | resource |
| [azurerm_kusto_script.ingestion_setup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kusto_script) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_blob.settings](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_blob) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_management_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_management_policy) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region (e.g. germanywestcentral) | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group where FinOpsHub resources will be deployed. Must be created by the caller (e.g. via ../ResourceGroup at root). | `string` | n/a | yes |
| adx\_disk\_encryption\_enabled | Encrypt the ADX cluster's VM disks (hot-cache data volumes + OS disk) at rest with Microsoft-managed keys. Secure-by-default true (CKV\_AZURE\_74). | `bool` | `true` | no |
| adx\_double\_encryption\_enabled | Enable infrastructure-level (double) encryption on the ADX cluster storage<br>(CKV\_AZURE\_75). OPT-IN: default false.<br><br>BREAKING / RECREATION: this property can only be set at cluster CREATION and<br>cannot be changed afterwards (Azure platform constraint — see<br>https://learn.microsoft.com/azure/data-explorer/cluster-encryption-double).<br>The azurerm provider marks it ForceNew, so flipping this on an EXISTING<br>cluster forces the cluster to be DESTROYED and RECREATED (raw ingested data<br>is lost unless re-ingested). It is therefore kept opt-in / default false so<br>it never destroys an existing FinOpsHub cluster implicitly. Set true on a<br>NEW deployment to get infrastructure-level double encryption from creation. | `bool` | `false` | no |
| adx\_hot\_cache\_days | Number of days for ADX hot cache | `number` | `31` | no |
| adx\_sku\_capacity | ADX cluster node count (1 for dev, 2+ for prod) | `number` | `1` | no |
| adx\_sku\_name | ADX cluster SKU name (e.g. Dev(No SLA)\_Standard\_D11\_v2 for dev, Standard\_D11\_v2 for prod) | `string` | `"Dev(No SLA)_Standard_D11_v2"` | no |
| adx\_soft\_delete\_days | Number of days for ADX soft delete retention | `number` | `365` | no |
| adx\_zones | Availability zones for the ADX cluster. If null, defaults to ["1","2","3"] for non-Dev SKUs and [] for Dev SKUs. | `list(string)` | `null` | no |
| cost\_management\_exports\_principal\_id | Principal ID of the Azure Cost Management Exports Service Principal (null = no role assignment) | `string` | `null` | no |
| enable\_data\_explorer | Deploy Azure Data Explorer cluster and databases | `bool` | `true` | no |
| enable\_public\_access | Enable public network access on storage and ADF. WARNING: bypasses firewall perimeter. Use Private Endpoints in production. | `bool` | `false` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| export\_retention\_days | Number of days to retain raw exports in msexports container (0 = delete after processing) | `number` | `0` | no |
| hub\_additional\_viewers | Extra Viewer principals on the Data Explorer Hub database (key = short<br>name, value = principal/object ID). Typically an application/managed<br>identity — e.g. Grafana's identity reading FinOps data.<br><br>NOTE: created with principal\_type = "App" (managed identities / service<br>principals). To grant an Entra GROUP or USER, this map isn't enough<br>(a Group would be created as App and rejected) — extend the module to a<br>per-entry principal\_type first. Ignored when enable\_data\_explorer = false. | `map(string)` | `{}` | no |
| ingestion\_retention\_months | Number of months to retain ingested data in ingestion container | `number` | `13` | no |
| name | Explicit module-level name override (escape hatch). If null, derived from naming convention via ../Naming. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| storage\_replication\_type | Replication type for the storage account (LRS, ZRS) | `string` | `"LRS"` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| workload | Workload identifier — typically 'finops' for FinOpsHub deployments. | `string` | `"finops"` | no |

## Outputs

| Name | Description |
|------|-------------|
| adx\_cluster\_id | The ID of the ADX cluster |
| adx\_cluster\_name | The name of the ADX cluster |
| adx\_cluster\_uri | The URI of the ADX cluster |
| adx\_ingestion\_uri | The data ingestion URI of the ADX cluster |
| data\_factory\_id | The ID of the Data Factory |
| data\_factory\_name | The name of the Data Factory |
| data\_factory\_principal\_id | The principal ID of the Data Factory managed identity |
| eventhub\_namespace\_id | The ID of the Event Hub Namespace |
| hub\_additional\_viewer\_ids | Map of hub\_additional\_viewers key => Kusto database principal assignment ID (empty when none / ADX disabled). |
| resource | The FinOps Hub storage account object (primary resource) |
| storage\_account\_id | The ID of the FinOps Hub storage account |
| storage\_account\_name | The name of the FinOps Hub storage account |
<!-- END_TF_DOCS -->
