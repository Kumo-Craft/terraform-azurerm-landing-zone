# AvdWorkspace

Deploys an AVD **Workspace** — the user-facing entry point that aggregates application groups (Desktop and RemoteApp) and exposes them in the AVD client. One workspace per logical environment is typical.

## Breaking changes (v0.2.34)

### `public_network_access_enabled` default flipped `true` → `false`

**Rationale**: CAF secure-by-default posture. The README already documented `false` as the recommended default; this aligns code with documentation.

**Migration**: callers relying on the previous default of `true` must explicitly pin `public_network_access_enabled = true` **before upgrading** if no Private Endpoint is wired. Without it, workspace feed access becomes PE-only and may break AVD client connections if Private Link is not configured.

**Recommended path**: deploy a `../PrivateEndpoint` module targeting the `feed` sub-resource of the workspace, then set `public_network_access_enabled = false` (the new default).

### Application group associations moved here from `AvdApplicationGroup`

`AvdApplicationGroup` v0.2.33 removed the `azurerm_virtual_desktop_workspace_application_group_association` resource and left a `removed { lifecycle.destroy = false }` tombstone. `AvdWorkspace` v0.2.34 is now the single source of truth for association binding via `var.application_group_associations`.

**Migration**: run `terraform state mv 'module.app_group.azurerm_virtual_desktop_workspace_application_group_association.this' 'module.workspace.azurerm_virtual_desktop_workspace_application_group_association.this["<key>"]'` per association, then remove the legacy `workspace_id` input from the `AvdApplicationGroup` call.

## Usage

### Standalone

```hcl
module "avd_ws" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/AvdWorkspace?ref=v0.2.34"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "weu"
  workload             = "main"
  location             = "westeurope"
  resource_group_name  = "rg-avd-nprd-weu-avd"

  friendly_name = "AVD nprd"
  description   = "Non-prod AVD workspace"

  application_group_associations = {
    "vdag-avd-nprd-weu-desktop" = "/subscriptions/.../applicationGroups/vdag-avd-nprd-weu-desktop"
  }

  lock = { kind = "CanNotDelete" }

  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AvdWorkspace"
}

dependency "dag" { config_path = "../dag-avd" }

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = "weu"
  location             = "westeurope"
  workload             = "main"
  resource_group_name  = "rg-${include.sub.locals.subscription_acronym}-${include.root.inputs.environment}-weu-avd"

  friendly_name = "AVD ${include.root.inputs.environment}"

  application_group_associations = {
    desktop = dependency.dag.outputs.id
  }

  tags = include.root.inputs.common_tags
}
```

## Naming Convention

`vdws-{subscription_acronym}-{environment}-{region_code}-{workload}` — overridable via `var.name`.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Required Inputs

| Name | Description |
|---|---|
| `location` | Azure region (control plane: `westeurope` for GWC users) |
| `resource_group_name` | Resource group |

## Key Optional Inputs

| Name | Default | Description |
|---|---|---|
| `friendly_name` | — | Display name shown in AVD clients |
| `description` | — | Long description |
| `application_group_associations` | `{}` | Map of logical name → app group resource ID to expose in this workspace |
| `public_network_access_enabled` | `false` | Set `true` only if no Private Endpoint wired (see Breaking changes above) |
| `lock` | `null` | Optional CanNotDelete / ReadOnly lock |
| `role_assignments` | `{}` | Map of workspace-scoped RBAC grants |
| `tags` | `{}` | Tags |

## Outputs

| Name | Description |
|---|---|
| `id` | Workspace resource ID |
| `name` | Workspace name |
| `resource` | Full workspace resource object |
| `association_ids` | Map of logical association name => association resource ID |
| `lock_id` | Management lock ID (null if no lock) |
| `role_assignment_ids` | Map of role assignment name => assignment ID |

## Notes

- A workspace exposes **application groups**, not host pools directly. Bind your Desktop and RemoteApp groups via `application_group_associations`.
- For private connectivity, add a Private Endpoint on the `feed` subresource and leave `public_network_access_enabled = false` (the default).
- AVD control plane resources (workspace, host pool, app groups) are **regional** — a single workspace can aggregate app groups from multiple regions.

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
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_virtual_desktop_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_workspace) | resource |
| [azurerm_virtual_desktop_workspace_application_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_workspace_application_group_association) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | ############################################################## REQUIRED VARIABLES ############################################################## | `string` | n/a | yes |
| resource\_group\_name | n/a | `string` | n/a | yes |
| application\_group\_associations | Map of application group associations. Key = logical name (e.g. 'desktop-prod-1', 'remoteapp-finance'). Value = the application group's ID (from AvdApplicationGroup.output.id). One association resource created per map entry. AVD architecture: workspace is the user-facing client surface ; app groups are entitlements ; this map binds them. | `map(string)` | `{}` | no |
| description | n/a | `string` | `null` | no |
| environment | n/a | `string` | `null` | no |
| friendly\_name | Display name shown in clients | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the workspace. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit workspace name. If null, computed automatically. | `string` | `null` | no |
| public\_network\_access\_enabled | Enable public access to the workspace. Set false when using Private Link (feed PE). | `bool` | `false` | no |
| region\_code | n/a | `string` | `null` | no |
| role\_assignments | Map of role assignments at the workspace scope. Workspace-level RBAC is less common than app-group-level (per MS Learn) but useful for AVD admin scenarios (e.g. workspace contributor grants). Default principal\_type='Group'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "Group")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym | `string` | `null` | no |
| tags | Tags | `map(string)` | `{}` | no |
| workload | Workload suffix | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| association\_ids | Map of logical association name => association resource ID |
| id | Workspace resource ID |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | Workspace name |
| resource | Full workspace resource object |
| role\_assignment\_ids | Map of role assignment logical name => role assignment ID |
<!-- END_TF_DOCS -->
