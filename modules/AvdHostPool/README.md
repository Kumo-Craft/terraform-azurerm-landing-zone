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
