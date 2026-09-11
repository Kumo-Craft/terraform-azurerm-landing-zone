# SecurityCenterWorkspace

Wraps `azurerm_security_center_workspace` to redirect a subscription's Microsoft Defender for Cloud telemetry to a central Log Analytics Workspace. Typically the ALZ Management LAW (from `../AlzManagement`).

## Usage

### Standalone

```hcl
module "security_center_workspace" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SecurityCenterWorkspace?ref=v0.2.44"

  subscription_id            = "00000000-0000-0000-0000-000000000000"  # bare GUID OR full /subscriptions/ path
  log_analytics_workspace_id = "/subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/law-mgmt"
}
```

### Terragrunt (composition with AlzManagement)

```hcl
dependency "alz_management" {
  config_path = "../alz-management"
}

inputs = {
  subscription_id            = local.subscription_id
  log_analytics_workspace_id = dependency.alz_management.outputs.law_id
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subscription_id | Subscription where the Defender for Cloud default workspace setting applies. Accepts either a bare GUID or the full `/subscriptions/<guid>` path. | `string` | -- | Yes |
| log_analytics_workspace_id | Full Azure resource ID of the Log Analytics Workspace receiving Defender for Cloud data. Must match the pattern `/subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/...`. | `string` | -- | Yes |

## Outputs

| Name | Description |
|------|-------------|
| id | Resource ID of the workspaceSettings (always `.../workspaceSettings/default`). |
| workspace_id | Log Analytics Workspace resource ID receiving Defender for Cloud data. |
| resource | Full `azurerm_security_center_workspace` resource object. |

## IAM Requirements

The deploying principal MUST have either:

- `Owner` role at subscription scope, OR
- A custom role with `Microsoft.Security/workspaceSettings/*` permission at subscription scope.

`Contributor` is NOT sufficient — the write action will return 403.

## Notes

- **One call per subscription.** Multiple `azurerm_security_center_workspace` resources targeting the same subscription scope will overwrite each other (last apply wins). Deploy one instance per subscription in your Terragrunt composition.

- **Family scope gap (F-6 from review):** This module covers ONLY workspace association. Defender plans (`azurerm_security_center_subscription_pricing`), settings (`azurerm_security_center_setting` for MCAS/WDATP), and contact notifications (`azurerm_security_center_contact`) are NOT exposed. Callers needing Defender Standard tier plans must wire those resources externally OR file a feature request for a `SecurityCenterSubscription` companion module.

- **Deprecation note:** `azurerm_security_center_auto_provisioning` is deprecated in azurerm 4.75.0 and will be removed in 5.0. This module does NOT use it — Defender plan + AMA via DCR is the replacement pattern (see `../AlzManagement` for DCR wiring).

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_security_center_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/security_center_workspace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| log\_analytics\_workspace\_id | Full Azure resource ID of the Log Analytics Workspace receiving Defender for Cloud data (e.g. the central law-mgm-{env}-gwc-01). | `string` | n/a | yes |
| subscription\_id | Subscription where the Defender for Cloud default workspace setting applies. Accepts either a bare GUID or the full /subscriptions/<guid> path. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| id | Resource ID of the workspaceSettings (always .../workspaceSettings/default). |
| resource | Full azurerm\_security\_center\_workspace resource object. |
| scope | Subscription scope this setting applies to. |
| workspace\_id | Log Analytics Workspace resource ID receiving Defender for Cloud data. |
<!-- END_TF_DOCS -->
