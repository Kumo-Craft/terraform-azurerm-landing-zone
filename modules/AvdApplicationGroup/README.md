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
