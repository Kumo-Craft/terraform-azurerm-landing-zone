# AlzManagement

Deploys the Azure Landing Zone management stack using the official `Azure/avm-ptn-alz-management/azurerm` module. Creates a Log Analytics Workspace, Automation Account, Data Collection Rules (Change Tracking, VM Insights, Defender SQL), Microsoft Sentinel, and User Assigned Managed Identities (LAW, AMA).

## Breaking changes (v0.2.37)

**`log_retention_days` default changed: 30 → 90**

The default retention period has been raised to align with the [Microsoft ALZ Management & Monitoring design area](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/management) recommendation of at least 90 days for operational logs.

**Cost impact**: Azure Log Analytics (PerGB2018 SKU) includes 31 days of free retention. Retention beyond 31 days is billed per GB per day. Callers currently relying on the 30-day default paid no retention fees; after upgrade, the workspace will retain logs for 90 days, incurring daily ingestion × 59 days of paid retention pricing.

**Migration**: Callers who want to keep 30-day retention must explicitly pin the value before upgrading:

```hcl
log_retention_days = 30
```

Otherwise, the next `terraform apply` will update the workspace retention from 30 to 90 days.

## Usage

### Standalone

```hcl
module "alz_management" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AlzManagement?ref=v0.2.37"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  location             = "germanywestcentral"

  create_resource_group  = true
  resource_group_workload = "management"

  log_ingestion_gb_per_day = 5
  log_daily_quota_gb       = 10
  log_retention_days       = 30

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AlzManagement"
}

inputs = {
  subscription_acronym   = include.sub.locals.subscription_acronym
  environment            = include.root.inputs.environment
  region_code            = include.root.inputs.region_code
  workload               = "01"
  location               = include.root.inputs.location
  create_resource_group  = true
  log_ingestion_gb_per_day = 5
  log_daily_quota_gb       = 10
  log_retention_days       = 30
  tags                   = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subscription_acronym | Subscription acronym (e.g. mgm, con) | `string` | -- | Yes |
| environment | Environment (e.g. prod, nprd) | `string` | -- | Yes |
| region_code | Region code (e.g. gwc, weu) | `string` | -- | Yes |
| workload | Workload suffix for naming | `string` | `"01"` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name. Required when create_resource_group = false. | `string` | `null` | No |
| create_resource_group | If true, creates the resource group inline. | `bool` | `false` | No |
| resource_group_workload | Workload name for RG naming when create_resource_group = true. | `string` | `"management"` | No |
| log_ingestion_gb_per_day | Expected log ingestion per day in GB. >100 = CapacityReservation SKU. | `number` | `5` | No |
| log_daily_quota_gb | Daily quota for log ingestion in GB | `number` | `10` | No |
| log_retention_days | Log Analytics retention in days (30–730). ALZ baseline >= 90 days. | `number` | `90` | No |
| law_internet_ingestion_enabled | Enable internet ingestion on LAW. Set to false after Private Endpoints are deployed. | `bool` | `true` | No |
| law_internet_query_enabled | Enable internet query on LAW. Set to false after Private Endpoints are deployed. | `bool` | `true` | No |
| law_local_authentication_enabled | Allow local (shared key) authentication on LAW. Best practice: false to force Azure AD only. | `bool` | `false` | No |
| aa_public_network_access_enabled | Allow public network access on Automation Account. Set to false for AMPLS. | `bool` | `false` | No |
| enable_cmk | Enable Customer Managed Keys for encryption | `bool` | `false` | No |
| tags | Tags to apply to all resources | `map(string)` | `{}` | No |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the LAW and RG. Set to null to skip. | `object({ kind = string, name = optional(string) })` | `null` | No |

## Outputs

| Name | Description |
|------|-------------|
| law_id | The ID of the Log Analytics Workspace |
| law_name | The name of the Log Analytics Workspace |
| law_workspace_id | The Workspace ID (GUID) of the Log Analytics Workspace |
| automation_account_id | The ID of the Automation Account — **null** (no AA is created, see `linked_automation_account_creation_enabled = false`) |
| automation_account_name | The name of the Automation Account — **null** (no AA is created) |
| dcr_vm_insights_id | Resource ID of the VM Insights Data Collection Rule |
| dcr_change_tracking_id | Resource ID of the Change Tracking & Inventory Data Collection Rule |
| dcr_defender_sql_id | Resource ID of the Defender for SQL Data Collection Rule |
| ama_identity_id | The ID of the AMA User Assigned Identity |
| resource_group_name | The name of the resource group |
| resource_group_id | Resource Group ID (inline-created or caller-provided, always populated) |
| lock_ids | Map of lock key => lock resource ID (keys: law, rg). Empty map when lock = null. |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
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
| alz\_management | Azure/avm-ptn-alz-management/azurerm | 0.9.0 |
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| naming\_component | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment (e.g. prod, nprd) | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| region\_code | Region code (e.g. gwc, weu) | `string` | n/a | yes |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | n/a | yes |
| aa\_public\_network\_access\_enabled | Allow public network access on Automation Account. Set to false for AMPLS. | `bool` | `false` | no |
| create\_resource\_group | If true, creates the resource group inline. If false, resource\_group\_name must reference an existing RG. | `bool` | `false` | no |
| enable\_cmk | Enable Customer Managed Keys for encryption | `bool` | `false` | no |
| enable\_sentinel | Onboard Microsoft Sentinel on this workspace. Set false when Sentinel lives in a dedicated Security subscription (CAF alignment). | `bool` | `true` | no |
| law\_internet\_ingestion\_enabled | Enable internet ingestion on LAW. Set to false after Private Endpoints are deployed. | `bool` | `true` | no |
| law\_internet\_query\_enabled | Enable internet query on LAW. Set to false after Private Endpoints are deployed. | `bool` | `true` | no |
| law\_local\_authentication\_enabled | Allow local (shared key) authentication on LAW. Best practice: false to force Azure AD only. | `bool` | `false` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the Management LAW and Resource Group. Set to null to skip. Same kind applied to both LAW and RG. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| log\_daily\_quota\_gb | Daily ingestion cap in GB. Use -1 for NO cap (unlimited); otherwise must be >= 1. | `number` | `10` | no |
| log\_ingestion\_gb\_per\_day | Expected log ingestion per day in GB (for SKU selection). >100 = CapacityReservation | `number` | `5` | no |
| log\_retention\_days | Log Analytics retention in days. ALZ baseline recommends >= 90 days (Microsoft ALZ Management & Monitoring design area). Free retention tier is 31 days; costs apply beyond that. | `number` | `90` | no |
| resource\_group\_name | Resource group name. Required when create\_resource\_group = false. | `string` | `null` | no |
| resource\_group\_workload | Workload name for RG naming convention when create\_resource\_group = true. | `string` | `"management"` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| workload | Workload suffix for naming | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| ama\_identity\_id | The ID of the AMA User Assigned Identity |
| automation\_account\_id | The ID of the Automation Account (null — no AA is created). |
| automation\_account\_name | The name of the Automation Account (null — no AA is created). |
| dcr\_change\_tracking\_id | Resource ID of the Change Tracking & Inventory Data Collection Rule. |
| dcr\_defender\_sql\_id | Resource ID of the Defender for SQL Data Collection Rule. |
| dcr\_vm\_insights\_id | Resource ID of the VM Insights Data Collection Rule. |
| law\_id | The ID of the Log Analytics Workspace |
| law\_name | The name of the Log Analytics Workspace |
| law\_workspace\_id | The Workspace ID (GUID) of the Log Analytics Workspace |
| lock\_ids | Map of lock key => lock resource ID (keys: law, rg). Empty map when var.lock = null. |
| resource\_group\_id | Resource Group ID. Returns the inline-created RG ID OR the caller-provided RG ID via AVM's resource\_group output. |
| resource\_group\_name | The name of the resource group |
<!-- END_TF_DOCS -->
