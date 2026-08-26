# AlzArchitecture

Deploys the Azure Landing Zone management group hierarchy, subscription placement, and policy assignments (AMBA monitoring, DDoS, Defender, Backup) using the official `Azure/avm-ptn-alz/azurerm` pattern module.

## Usage

### Standalone

```hcl
module "alz_architecture" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/AlzArchitecture?ref=v0.2.36"

  architecture_name   = "prod"
  management_root_id  = "/providers/Microsoft.Management/managementGroups/090a1bf9-58cc-49fa-8a9e-3f7b0a100fa9"
  location            = "germanywestcentral"

  subscription_placement = {
    management = {
      subscription_id       = "00000000-0000-0000-0000-000000000001"
      management_group_name = "mg-mgmt-prod"
    }
    connectivity = {
      subscription_id       = "00000000-0000-0000-0000-000000000002"
      management_group_name = "mg-conn-prod"
    }
  }

  management_subscription_id   = "00000000-0000-0000-0000-000000000001"
  connectivity_subscription_id = "00000000-0000-0000-0000-000000000002"
  ddos_protection_plan_id      = "/subscriptions/.../providers/Microsoft.Network/ddosProtectionPlans/ddos-prod"
  ama_identity_id              = "/subscriptions/.../userAssignedIdentities/id-mgm-prod-gwc-ama"
  action_group_ids             = ["/subscriptions/.../actionGroups/ag-mgm-prod-gwc-ama"]
  log_analytics_workspace_id   = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01"
  email_security_contact       = "security@example.com"
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AlzArchitecture"
}

inputs = {
  architecture_name              = include.root.inputs.environment
  management_root_id             = include.sub.locals.tenant_root_id
  location                       = include.root.inputs.location
  subscription_placement         = include.sub.locals.subscription_placement
  management_subscription_id     = include.sub.locals.management_subscription_id
  connectivity_subscription_id   = include.sub.locals.connectivity_subscription_id
  ddos_protection_plan_id        = dependency.ddos.outputs.id
  ama_identity_id                = dependency.id_ama.outputs.id
  action_group_ids               = [dependency.action_group.outputs.id]
  log_analytics_workspace_id     = dependency.law.outputs.id
  email_security_contact         = "security@example.com"
}
```

## AVM module version note

This module wraps `Azure/avm-ptn-alz/azurerm`. The pin was bumped from `0.13.0` to `0.21.0` in v0.2.36. Version 0.21.0 brings the ALZ v2025 library (reference `platform/alz@2026.01.3` + `platform/amba@2025.05.0`) and adds four new optional inputs (`schema_validation_enabled`, `subscription_placement_destroy_behavior`, `management_groups_dependencies`, `resource_types`). All existing inputs and `policy_default_values` keys are unchanged between 0.13.0 and 0.21.0.

## Subscription placement

The Identity subscription (and any other platform subscription) is wired via the generic `subscription_placement` map input. There is no dedicated `identity_subscription_id` variable — use the map key of your choice:

```hcl
subscription_placement = {
  identity = { subscription_id = "...", management_group_name = "mg-idt-prod" }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| alz | ~> 0.21 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| architecture_name | ALZ architecture name | `string` | `"prod"` | No |
| management_root_id | Parent management group ID (tenant root) | `string` | -- | Yes |
| location | Azure region | `string` | -- | Yes |
| management_group_hierarchy_settings | Tenant-level hierarchy settings. Sets default MG for new subs and restricts MG creation. | `object({ default_management_group_name = string, require_authorization_for_group_creation = optional(bool, true), update_existing = optional(bool, false) })` | `null` | No |
| subscription_placement | Map of subscription placements in management groups | `map(object({ subscription_id = string, management_group_name = string }))` | -- | Yes |
| management_subscription_id | Management subscription ID | `string` | -- | Yes |
| connectivity_subscription_id | Connectivity subscription ID | `string` | -- | Yes |
| alert_severity | Severity levels for alert notifications | `list(string)` | `["Sev0", "Sev1", "Sev2", "Sev3", "Sev4"]` | No |
| email_security_contact | Email for Defender for Cloud security contact | `string` | `""` | No |
| amba_resource_group_name | Resource group name for AMBA monitoring | `string` | `"rg-amba-monitoring-001"` | No |
| mdfc_export_resource_group_name | RG name for the MDFC continuous-export (Deploy-MDFC-Config DINE) | `string` | `"rg-alz-mdfc-export"` | No |
| service_health_resource_group_name | RG name for the Service Health alerts (Deploy-SvcHealth-BuiltIn DINE) | `string` | `"rg-alz-service-health"` | No |
| amba_resource_group_tags | Tags for the AMBA resource group | `map(string)` | `{}` | No |
| amba_disable_tag_name | Tag name to disable monitoring at resource level | `string` | `"MonitorDisable"` | No |
| amba_disable_tag_values | Tag values to disable monitoring | `list(string)` | `["true", "Test", "Dev", "Sandbox"]` | No |
| action_group_email | Action group email addresses | `list(string)` | `[]` | No |
| ddos_protection_plan_id | DDoS Protection Plan resource ID | `string` | -- | Yes |
| ama_identity_id | AMA User Assigned Identity ID | `string` | -- | Yes |
| action_group_ids | List of Action Group IDs | `list(string)` | -- | Yes |
| log_analytics_workspace_id | Full resource ID of the Log Analytics Workspace | `string` | -- | Yes |
| dcr_vm_insights_id | Full resource ID of the VM Insights DCR (AlzManagement output `dcr_vm_insights_id`) | `string` | -- | Yes |
| dcr_change_tracking_id | Full resource ID of the Change Tracking & Inventory DCR (AlzManagement output `dcr_change_tracking_id`) | `string` | -- | Yes |
| dcr_defender_sql_id | Full resource ID of the Defender for SQL DCR (AlzManagement output `dcr_defender_sql_id`) | `string` | -- | Yes |
| backup_exclusion_tags | Tags to exclude from VM Backup policy | `list(string)` | `["NoBackup"]` | No |
| private_dns_zone_resource_group_name | Resource group for private DNS zones | `string` | `""` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource | Full ALZ architecture module output object |
| management_group_ids | Map of management group IDs |
| policy_assignment_identity_ids | Map of policy assignment identity principal IDs |
| policy_assignment_resource_ids | Map of policy assignment name => resource ID (consumed by downstream PolicyExemption / PolicyRemediation modules at the LZ scope). |
| policy_definition_resource_ids | Map of policy definition name => resource ID. |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| alz | ~> 0.21 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| alz\_architecture | Azure/avm-ptn-alz/azurerm | 0.21.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| action\_group\_ids | List of Action Group IDs | `list(string)` | n/a | yes |
| ama\_identity\_id | AMA User Assigned Identity ID | `string` | n/a | yes |
| connectivity\_subscription\_id | Connectivity subscription ID | `string` | n/a | yes |
| dcr\_change\_tracking\_id | Full resource ID of the Change Tracking & Inventory Data Collection Rule (AlzManagement output dcr\_change\_tracking\_id). | `string` | n/a | yes |
| dcr\_defender\_sql\_id | Full resource ID of the Defender for SQL Data Collection Rule (AlzManagement output dcr\_defender\_sql\_id). | `string` | n/a | yes |
| dcr\_vm\_insights\_id | Full resource ID of the VM Insights Data Collection Rule (AlzManagement output dcr\_vm\_insights\_id). | `string` | n/a | yes |
| ddos\_protection\_plan\_id | DDoS Protection Plan resource ID | `string` | n/a | yes |
| location | Default Azure region for DINE policy remediation deployments (e.g. AMBA resource group, Log Analytics, DCR). Not a management group resource attribute — management groups are global. | `string` | n/a | yes |
| log\_analytics\_workspace\_id | Full resource ID of the Log Analytics Workspace | `string` | n/a | yes |
| management\_root\_id | Parent management group ID (tenant root) | `string` | n/a | yes |
| management\_subscription\_id | Management subscription ID | `string` | n/a | yes |
| subscription\_placement | Map of subscription placements in management groups | <pre>map(object({<br>    subscription_id       = string<br>    management_group_name = string<br>  }))</pre> | n/a | yes |
| action\_group\_email | Action group email addresses | `list(string)` | `[]` | no |
| alert\_severity | Severity levels for alert notifications | `list(string)` | <pre>[<br>  "Sev0",<br>  "Sev1",<br>  "Sev2",<br>  "Sev3",<br>  "Sev4"<br>]</pre> | no |
| amba\_disable\_tag\_name | Tag name to disable monitoring at resource level | `string` | `"MonitorDisable"` | no |
| amba\_disable\_tag\_values | Tag values to disable monitoring | `list(string)` | <pre>[<br>  "true",<br>  "Test",<br>  "Dev",<br>  "Sandbox"<br>]</pre> | no |
| amba\_resource\_group\_name | Resource group name for AMBA monitoring | `string` | `"rg-amba-monitoring-001"` | no |
| amba\_resource\_group\_tags | Tags for the AMBA resource group | `map(string)` | `{}` | no |
| architecture\_name | ALZ architecture name | `string` | `"core"` | no |
| backup\_exclusion\_tags | Tags to exclude from VM Backup policy | `list(string)` | <pre>[<br>  "NoBackup"<br>]</pre> | no |
| defender\_plans | Defender for Cloud plan activation, passed to Deploy-MDFC-Config-H224 via<br>policy\_assignments\_to\_modify. Each plan value must be either<br>"DeployIfNotExists" (enables the plan at Standard pricing) or "Disabled"<br>(skips the plan).<br><br>Default: all plans enabled (pay-per-use with 0 resources ≈ 0 cost,<br>auto-coverage when a workload is deployed). Override individual plans<br>by setting them to "Disabled" if your org has a specific exclusion.<br><br>Note: Defender for APIs is not exposed by the Deploy-MDFC-Config\_20240319<br>policySet and must be managed out-of-band (or via a future policy version). | <pre>object({<br>    app_services                      = optional(string, "DeployIfNotExists")<br>    arm                               = optional(string, "DeployIfNotExists")<br>    containers                        = optional(string, "DeployIfNotExists")<br>    cosmos_dbs                        = optional(string, "DeployIfNotExists")<br>    cspm                              = optional(string, "DeployIfNotExists")<br>    key_vault                         = optional(string, "DeployIfNotExists")<br>    oss_db                            = optional(string, "DeployIfNotExists")<br>    servers                           = optional(string, "DeployIfNotExists")<br>    servers_vulnerability_assessments = optional(string, "DeployIfNotExists")<br>    sql                               = optional(string, "DeployIfNotExists")<br>    sql_on_vm                         = optional(string, "DeployIfNotExists")<br>    storage                           = optional(string, "DeployIfNotExists")<br>  })</pre> | `{}` | no |
| email\_security\_contact | Email for Defender for Cloud security contact | `string` | `""` | no |
| management\_group\_hierarchy\_settings | Tenant-level hierarchy settings. Sets default MG for new subs and restricts MG creation. | <pre>object({<br>    default_management_group_name            = string<br>    require_authorization_for_group_creation = optional(bool, true)<br>    update_existing                          = optional(bool, false)<br>  })</pre> | `null` | no |
| mdfc\_export\_resource\_group\_name | RG name for the MDFC continuous-export automation (created per subscription by the Deploy-MDFC-Config DINE policy). | `string` | `"rg-alz-mdfc-export"` | no |
| policy\_assignment\_non\_compliance\_message\_settings | Default non-compliance message settings applied to policy assignments by the alz provider. Empty = AVM defaults. | <pre>object({<br>    default_message = optional(string)            # null = pas de message par défaut (comportement AVM backwards-compat)<br>    merge_mode      = optional(string, "replace") # doit rester "replace" | "prefer_existing", jamais null (validation AVM)<br>  })</pre> | `{}` | no |
| private\_dns\_zone\_resource\_group\_name | Resource group for private DNS zones. Null means no specific RG is required by the DINE policy (distinct from empty string). | `string` | `null` | no |
| retries | Retry settings forwarded to avm-ptn-alz (eventual consistency on fresh MG/policy/role deploys). Empty = AVM defaults. | `any` | `{}` | no |
| service\_health\_resource\_group\_name | RG name for the Service Health alerts (created per subscription by the Deploy-SvcHealth-BuiltIn DINE policy). | `string` | `"rg-alz-service-health"` | no |
| subscription\_placement\_destroy\_behavior | Where subscriptions go when their placement is destroyed. One of: parent, intermediate\_root, custom, default. | `string` | `"default"` | no |
| subscription\_placement\_destroy\_custom\_target\_management\_group\_id | Target management group id for subscriptions on destroy when subscription\_placement\_destroy\_behavior = "custom". | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| management\_group\_ids | Map of management group IDs |
| policy\_assignment\_identity\_ids | Map of policy assignment identity principal IDs |
| policy\_assignment\_resource\_ids | Map of policy assignment name => resource ID (consumed by downstream PolicyExemption / PolicyRemediation modules at the LZ scope). |
| policy\_definition\_resource\_ids | Map of policy definition name => resource ID. |
| resource | Full ALZ architecture module output object |
<!-- END_TF_DOCS -->
