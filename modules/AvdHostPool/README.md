# AvdHostPool

Deploys an Azure Virtual Desktop **Host Pool** with optional auto-rotating **registration token** for session-host enrollment. Pooled (Win11 multi-session) and Personal pool types supported. Includes optional resource lock and RBAC role assignments.

## Breaking changes (v0.2.31)

### `public_network_access` default flipped to `"Disabled"`

CAF secure-by-default guidance requires the AVD control plane to be private where possible. v0.2.31 flips the default from `"Enabled"` to `"Disabled"` to align with this posture.

**Impact for callers**: If your existing deployment relied on the old default (`public_network_access = "Enabled"`), upgrading will change the host pool's control plane to PE-only on first plan/apply. This **may break Azure Portal access** and session host registration if no Private Endpoint is wired to the host pool.

**Migration recipe**:

1. **Before upgrading**: pin the legacy value explicitly in your caller config:
   ```hcl
   module "avd_pool" {
     source                = "..."
     public_network_access = "Enabled"   # pin legacy default before upgrading
     # other args...
   }
   ```
2. Upgrade to v0.2.31. The pin overrides the new default — no control plane change.
3. **Recommended path to full private connectivity**:
   - Deploy a Private Endpoint for the host pool via `../PrivateEndpoint` targeting the `connection` subresource.
   - Then switch (or omit the pin to accept) `public_network_access = "Disabled"`.
4. **For NEW deployments**: omit the variable to get the secure default `"Disabled"` and wire a Private Endpoint from day one.

## Usage

### Standalone

```hcl
module "avd_pool" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AvdHostPool?ref=v0.2.31"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "weu"
  workload             = "pooled"
  location             = "westeurope"
  resource_group_name  = "rg-avd-nprd-weu-avd"

  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 8
  preferred_app_group_type = "Desktop"
  start_vm_on_connect      = true
  public_network_access    = "Disabled"

  # Token rotated automatically every registration_expiration_hours
  create_registration_info       = true
  registration_expiration_hours  = 48

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AvdHostPool"
}

dependency "rg_avd" {
  config_path = "../rg-avd"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = "weu"
  location             = "westeurope"
  workload             = "pooled"
  resource_group_name  = dependency.rg_avd.outputs.name

  type                     = "Pooled"
  maximum_sessions_allowed = 8
  start_vm_on_connect      = true
  public_network_access    = "Disabled"

  create_registration_info      = true
  registration_expiration_hours = 48

  tags = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Naming Convention

`vdpool-{subscription_acronym}-{environment}-{region_code}-{workload}` — overridable via `var.name`.

## Required Inputs

| Name | Type | Description |
|---|---|---|
| `location` | `string` | Azure region (control plane: `westeurope` for GWC users) |
| `resource_group_name` | `string` | Resource group |

## Key Optional Inputs

| Name | Default | Description |
|---|---|---|
| `type` | `"Pooled"` | `"Pooled"` or `"Personal"` |
| `load_balancer_type` | `"BreadthFirst"` | Pooled load distribution: `BreadthFirst`, `DepthFirst`, or `Persistent` (Personal only) |
| `maximum_sessions_allowed` | `8` | Pooled only — concurrent sessions per session host |
| `preferred_app_group_type` | `"Desktop"` | `"Desktop"`, `"RailApplications"`, or `"None"` |
| `personal_desktop_assignment_type` | `null` | Personal pools only: `"Automatic"` or `"Direct"` |
| `start_vm_on_connect` | `true` | Wake deallocated session hosts on connection (pairs with Autoscale) |
| `public_network_access` | `"Disabled"` | **BREAKING (v0.2.31)** — set `"Enabled"` to restore legacy behaviour; see breaking changes above |
| `create_registration_info` | `false` | Generate a token for session host DSC registration |
| `registration_expiration_hours` | `48` | Token lifetime; rotation happens via `time_rotating` and `replace_triggered_by` on each apply that elapses the window |
| `scheduled_agent_updates` | `null` | Optional maintenance window for AVD agent updates — `{ enabled, timezone, use_session_host_timezone, schedule = [{ day_of_week, hour_of_day }] }` (max 2 schedule entries) |
| `lock` | `null` | Resource lock: `{ kind = "CanNotDelete"\|"ReadOnly", name = optional }` |
| `role_assignments` | `{}` | Map of RBAC grants at host pool scope — `{ role_definition_id_or_name, principal_id, principal_type = "Group", ... }` |

## Outputs

- `id` — Host pool resource ID
- `name` — Host pool name
- `registration_token` — `(sensitive)` token consumed by `AvdSessionHost.hostpool_registration_token`
- `lock_id` — Management lock ID (null if `var.lock` is null)
- `role_assignment_ids` — Map of logical name => role assignment ID

## Notes

- The registration token **rotates** when the rotation window elapses and a `terraform apply` runs. Schedule a CI apply at least once per rotation period to keep the token fresh; otherwise new session hosts cannot enroll once the token expires.
- AVD control plane is **regional** (no GWC) — typical pattern is to deploy the pool/workspace/app group in `westeurope` while session hosts run in `germanywestcentral`.
- For private connectivity, set `public_network_access = "Disabled"` and add a Private Endpoint on the `connection` subresource via `../PrivateEndpoint`.
- `personal_desktop_assignment_type` is only meaningful when `type = "Personal"`. For `"Pooled"` pools it is automatically set to `null` by the module regardless of the variable value.

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
| [azurerm_virtual_desktop_host_pool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_host_pool) | resource |
| [azurerm_virtual_desktop_host_pool_registration_info.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_host_pool_registration_info) | resource |
| [time_rotating.registration_token](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/rotating) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| create\_registration\_info | If true, creates a registration token usable by session host DSC extension to register to the host pool. | `bool` | `false` | no |
| custom\_rdp\_properties | Semicolon-separated RDP properties (e.g. "audiocapturemode:i:1;camerastoredirect:s:*") | `string` | `null` | no |
| description | n/a | `string` | `null` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| friendly\_name | Display name shown in clients | `string` | `null` | no |
| load\_balancer\_type | Load balancer algorithm: BreadthFirst, DepthFirst, or Persistent (Personal only) | `string` | `"BreadthFirst"` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly). Set to null to skip lock creation. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| maximum\_sessions\_allowed | Max concurrent sessions per session host (Pooled only). MS recommends 8-16 for Win11 multi-session. | `number` | `8` | no |
| name | Explicit host pool name. If null, computed automatically. | `string` | `null` | no |
| personal\_desktop\_assignment\_type | Personal pool desktop assignment type — 'Automatic' (Azure auto-assigns first connecting user) or 'Direct' (manual assignment). Only relevant when var.type == "Personal"; ignored otherwise. | `string` | `null` | no |
| preferred\_app\_group\_type | Preferred app group type: 'Desktop' (full desktop session), 'RailApplications' (RemoteApp individual apps), or 'None' (no default app group). | `string` | `"Desktop"` | no |
| public\_network\_access | Controls public endpoint: 'Enabled', 'Disabled', 'EnabledForClientsOnly', 'EnabledForSessionHostsOnly'. | `string` | `"Disabled"` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| registration\_expiration\_hours | Registration token lifetime in hours (1-720). Defaults to 48h. | `number` | `48` | no |
| role\_assignments | Map of role assignments to apply at the host pool scope. Key is a logical name. Default principal\_type for AVD is 'Group' (Desktop Virtualization User role is GA-restricted to AAD users/groups). | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "Group")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| scheduled\_agent\_updates | Optional scheduled agent updates configuration for the host pool — pins session host agent updates to a maintenance window. Set to null to use Azure default (unmanaged). | <pre>object({<br>    enabled                   = optional(bool, false)<br>    timezone                  = optional(string)<br>    use_session_host_timezone = optional(bool, false)<br>    schedule = optional(list(object({<br>      day_of_week = string<br>      hour_of_day = number<br>    })), [])<br>  })</pre> | `null` | no |
| start\_vm\_on\_connect | Wake session hosts from deallocated state on incoming connection (pairs with Autoscale) | `bool` | `true` | no |
| subscription\_acronym | Subscription acronym (e.g. avd, api) | `string` | `null` | no |
| tags | Tags | `map(string)` | `{}` | no |
| type | Host pool type: Pooled or Personal | `string` | `"Pooled"` | no |
| validate\_environment | Mark as validation environment (receives AVD agent updates first) | `bool` | `false` | no |
| workload | Workload suffix (e.g. pooled, personal) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Host pool resource ID |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | Host pool name |
| registration\_token | Registration token for session host DSC extension (null if create\_registration\_info=false) |
| resource | Full host pool resource object |
| role\_assignment\_ids | Map of role assignment logical name => role assignment ID |
<!-- END_TF_DOCS -->
