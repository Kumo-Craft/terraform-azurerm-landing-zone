# AlzArchitecture

Deploys the Azure Landing Zone management group hierarchy, subscription placement, and policy assignments (AMBA monitoring, DDoS, Defender, Backup) using the official `Azure/avm-ptn-alz/azurerm` pattern module.

## Usage

### Standalone

```hcl
module "alz_architecture" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AlzArchitecture?ref=v0.2.36"

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
