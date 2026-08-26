# AvdApplicationGroup

Deploys an Azure Virtual Desktop **Application Group** (Desktop or RemoteApp) bound to a host pool. Application groups are the unit assigned to users/groups in AVD — they expose either the full desktop session or a curated set of published applications.

## Breaking changes (v0.2.33)

### F-5: Workspace association removed — ownership transferred to AvdWorkspace

The `azurerm_virtual_desktop_workspace_application_group_association` resource has been removed from this module. Workspace association ownership now belongs exclusively to the **AvdWorkspace** module (v0.2.33+).

**Migration recipe for callers currently using `var.workspace_id`:**

1. Remove `workspace_id` from your AvdApplicationGroup inputs.
2. Pass the application group's `output.id` to AvdWorkspace's `application_group_ids` input (AvdWorkspace v0.2.33+ will expose this contract — flag for AvdWorkspace re-review next).
3. Before upgrading, migrate the existing association from state:
   ```
   terraform state mv \
     module.avd_app_group.azurerm_virtual_desktop_workspace_application_group_association.this[0] \
     module.avd_workspace.azurerm_virtual_desktop_workspace_application_group_association.this["<key>"]
   ```
   (The exact target path depends on the final AvdWorkspace shape.)
4. A `removed { lifecycle.destroy = false }` tombstone block is present in this module — even without a state migration, the actual Azure resource is NOT deleted on first plan, giving callers time to migrate state.

This follows the same tombstone approach used by NetworkWatcher v0.2.1, KeyVaultStack v0.2.2, NetworkStack v0.2.8, and PrivateDnsZones v0.2.9.

## Usage

### Standalone

```hcl
module "avd_app_group" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AvdApplicationGroup?ref=v0.2.33"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "weu"
  workload             = "desktop"
  location             = "westeurope"
  resource_group_name  = "rg-avd-nprd-weu-avd"

  host_pool_id = "/subscriptions/.../hostPools/vdpool-avd-nprd-weu-pooled"
  type         = "Desktop" # or "RemoteApp"

  friendly_name = "AVD Desktop nprd"

  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AvdApplicationGroup"
}

dependency "host_pool" {
  config_path = "../hp-avd"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = "weu"
  location             = "westeurope"
  workload             = "desktop"
  resource_group_name  = "rg-${include.sub.locals.subscription_acronym}-${include.root.inputs.environment}-weu-avd"

  host_pool_id  = dependency.host_pool.outputs.id
  type          = "Desktop"
  friendly_name = "AVD Desktop ${include.root.inputs.environment}"

  tags = include.root.inputs.common_tags
}
```

## Naming Convention

`vdag-{subscription_acronym}-{environment}-{region_code}-{workload}` — overridable via `var.name`.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Required Inputs

| Name | Type | Description |
|---|---|---|
| `location` | `string` | Azure region |
| `resource_group_name` | `string` | Resource group |
| `host_pool_id` | `string` | Host pool resource ID this app group binds to |

## Key Optional Inputs

| Name | Default | Description |
|---|---|---|
| `type` | `"Desktop"` | `"Desktop"` (full session) or `"RemoteApp"` (curated apps) |
| `friendly_name` | — | Display name shown in AVD clients |
| `description` | — | Long description |
| `default_desktop_display_name` | `null` | Display name for the default Desktop item (Desktop groups only) |
| `applications` | `{}` | Map of RemoteApp applications to publish (RemoteApp groups only) |
| `lock` | `null` | Resource lock: `{ kind = "CanNotDelete" }` or `{ kind = "ReadOnly" }` |
| `role_assignments` | `{}` | Map of RBAC role assignments at the app group scope |
| `tags` | `{}` | Resource tags |

## Outputs

| Name | Description |
|---|---|
| `id` | Application Group resource ID |
| `name` | Application Group name |
| `resource` | Full application group resource object |
| `application_ids` | Map of application logical key => resource ID (RemoteApp groups only) |
| `lock_id` | Management lock ID (null if var.lock is null) |
| `role_assignment_ids` | Map of role assignment logical name => role assignment ID |

## Notes

- A **Desktop** app group is implicitly created with every host pool but can be replaced/customized.
- A pool can have multiple **RemoteApp** groups (each exposing a curated subset).
- The canonical AVD RBAC pattern is to assign **Desktop Virtualization User** at the application group scope via `var.role_assignments` (not at the host pool scope).
- Workspace association is handled by the `AvdWorkspace` module — see breaking change note above.

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
| [azurerm_virtual_desktop_application.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_application) | resource |
| [azurerm_virtual_desktop_application_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_application_group) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| host\_pool\_id | Host pool resource ID to bind this app group to | `string` | n/a | yes |
| location | ############################################################## REQUIRED VARIABLES ############################################################## | `string` | n/a | yes |
| resource\_group\_name | n/a | `string` | n/a | yes |
| applications | Map of RemoteApp applications to publish. Logical key -> app definition. Only honored when var.type == "RemoteApp". Each app: name (display key in AVD), path (full executable path on the session host), command\_line\_argument\_policy (DoNotAllow/Allow/Require), optional friendly\_name + description + command\_line\_arguments + icon\_path + icon\_index + show\_in\_portal. | <pre>map(object({<br>    name                         = string<br>    path                         = string<br>    command_line_argument_policy = string<br>    friendly_name                = optional(string, null)<br>    description                  = optional(string, null)<br>    command_line_arguments       = optional(string, null)<br>    icon_path                    = optional(string, null)<br>    icon_index                   = optional(number, 0)<br>    show_in_portal               = optional(bool, true)<br>  }))</pre> | `{}` | no |
| default\_desktop\_display\_name | Display name for the default Desktop item shown in the AVD client. Only meaningful when var.type == "Desktop". Ignored otherwise. | `string` | `null` | no |
| description | n/a | `string` | `null` | no |
| environment | n/a | `string` | `null` | no |
| friendly\_name | n/a | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the application group. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit app group name. If null, computed automatically. | `string` | `null` | no |
| region\_code | n/a | `string` | `null` | no |
| role\_assignments | Map of role assignments at the application group scope. CANONICAL AVD RBAC SCOPE: 'Desktop Virtualization User' role assigned here grants end-users access to launch desktops/RemoteApps. Default principal\_type='Group' (AVD standard — AAD security groups, not individual users). | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "Group")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | n/a | `string` | `null` | no |
| tags | Tags | `map(string)` | `{}` | no |
| type | Application group type: Desktop or RemoteApp | `string` | `"Desktop"` | no |
| workload | Workload suffix (e.g. desktop, remoteapp) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| application\_ids | Map of application logical key => application resource ID (populated for RemoteApp groups only) |
| id | Application group resource ID |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | Application group name |
| resource | Full application group resource object |
| role\_assignment\_ids | Map of role assignment logical name => role assignment ID |
<!-- END_TF_DOCS -->
