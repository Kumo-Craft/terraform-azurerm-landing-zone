# AvdScalingPlan

Deploys an AVD **Autoscale Plan** that controls session host VM lifecycle (start/stop/drain) on a schedule. Reduces compute costs by deallocating VMs during low-usage hours and waking them on demand or on a ramp-up schedule.

## Usage

### Standalone

```hcl
module "avd_scaling" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AvdScalingPlan?ref=v0.2.35"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "weu"
  workload             = "pooled"
  location             = "westeurope"
  resource_group_name  = "rg-avd-nprd-weu-avd"

  time_zone = "Romance Standard Time"

  schedules = {
    weekday = {
      days_of_week                                = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      ramp_up_start_time                          = "07:00"
      ramp_up_load_balancing_algorithm            = "BreadthFirst"
      ramp_up_minimum_hosts_percent               = 20    # optional after F-10
      ramp_up_capacity_threshold_percent          = 60    # optional after F-10
      peak_start_time                             = "09:00"
      peak_load_balancing_algorithm               = "DepthFirst"
      ramp_down_start_time                        = "18:00"
      ramp_down_load_balancing_algorithm          = "DepthFirst"
      ramp_down_minimum_hosts_percent             = 10
      ramp_down_capacity_threshold_percent        = 90
      ramp_down_force_logoff_users                = false
      ramp_down_wait_time_minutes                 = 30
      ramp_down_notification_message              = "You will be logged off in 30 minutes."
      ramp_down_stop_hosts_when                   = "ZeroSessions"
      off_peak_start_time                         = "20:00"
      off_peak_load_balancing_algorithm           = "DepthFirst"
    }
  }

  host_pool_associations = {
    "vdpool-avd-nprd-weu-pooled" = {
      hostpool_id          = "/subscriptions/.../hostPools/vdpool-avd-nprd-weu-pooled"
      scaling_plan_enabled = true
    }
  }

  lock = { kind = "CanNotDelete" }

  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AvdScalingPlan"
}

dependency "host_pool" { config_path = "../hp-avd" }

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = "weu"
  location             = "westeurope"
  workload             = "pooled"
  resource_group_name  = "rg-${include.sub.locals.subscription_acronym}-${include.root.inputs.environment}-weu-avd"

  time_zone = "Romance Standard Time"

  schedules = {
    weekday = {
      days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      ramp_up_start_time                   = "07:00"
      ramp_up_load_balancing_algorithm     = "BreadthFirst"
      peak_start_time                      = "09:00"
      peak_load_balancing_algorithm        = "DepthFirst"
      ramp_down_start_time                 = "18:00"
      ramp_down_load_balancing_algorithm   = "DepthFirst"
      ramp_down_minimum_hosts_percent      = 10
      ramp_down_capacity_threshold_percent = 90
      ramp_down_force_logoff_users         = false
      ramp_down_wait_time_minutes          = 30
      ramp_down_notification_message       = "You will be logged off in 30 minutes."
      ramp_down_stop_hosts_when            = "ZeroSessions"
      off_peak_start_time                  = "20:00"
      off_peak_load_balancing_algorithm    = "DepthFirst"
    }
  }

  host_pool_associations = {
    pooled = {
      hostpool_id          = dependency.host_pool.outputs.id
      scaling_plan_enabled = true
    }
  }

  tags = include.root.inputs.common_tags
}
```

## Naming Convention

`vdscaling-{subscription_acronym}-{environment}-{region_code}-{workload}` — overridable via `var.name`.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Required Inputs

| Name | Description |
|---|---|
| `location` | Azure region (must match host pool region) |
| `resource_group_name` | Resource group name |
| `schedules` | Map of scaling plan schedule objects (at least one required) |
| `host_pool_associations` | Map of host pool associations (`hostpool_id`, `scaling_plan_enabled`) |

## Key Optional Inputs

| Name | Default | Description |
|---|---|---|
| `name` | `null` | Explicit scaling plan name (overrides convention naming) |
| `subscription_acronym` | `null` | Used for convention naming |
| `environment` | `null` | Used for convention naming |
| `region_code` | `null` | Used for convention naming |
| `workload` | `"pooled"` | Used for convention naming |
| `time_zone` | `"W. Europe Standard Time"` | Windows time zone name (IANA not accepted) |
| `friendly_name` | `null` | Display name |
| `description` | `null` | Plan description |
| `exclusion_tag` | `null` | Tag name to exclude hosts from autoscale |
| `lock` | `null` | Optional CanNotDelete / ReadOnly resource lock |
| `role_assignments` | `{}` | Map of scaling-plan-scoped RBAC grants |
| `tags` | `{}` | Tags |

## Outputs

| Name | Description |
|---|---|
| `id` | Scaling plan resource ID |
| `name` | Scaling plan name |
| `resource` | Full scaling plan resource object |
| `lock_id` | Management lock ID (null if no lock) |
| `role_assignment_ids` | Map of role assignment name => assignment ID |

## Notes

- **AVD Autoscale prerequisite**: the AVD service principal needs *Desktop Virtualization Power On Off Contributor* on the session host subscription. The repo deploys this via the `RbacAssignments` module.
- **start_vm_on_connect** must be enabled on the host pool (`AvdHostPool.start_vm_on_connect = true`) for ramp-up to wake deallocated VMs.
- **time_zone** must be a Windows time zone name (e.g. `"W. Europe Standard Time"`, `"Romance Standard Time"`). IANA zone names (e.g. `"Europe/Amsterdam"`) are rejected by the Azure API.
- For **Personal** pools, only a subset of schedule fields are honored (no peak load balancing). A separate schedule shape for Personal autoscale (azurerm 4.20+ GA) is tracked for a future release.

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
| [azurerm_virtual_desktop_scaling_plan.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_scaling_plan) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| host\_pool\_associations | Map key => { hostpool\_id, scaling\_plan\_enabled } | <pre>map(object({<br>    hostpool_id          = string<br>    scaling_plan_enabled = optional(bool, true)<br>  }))</pre> | n/a | yes |
| location | Must match the host pool region. | `string` | n/a | yes |
| resource\_group\_name | n/a | `string` | n/a | yes |
| schedules | Map of scaling plan schedules. For Pooled host pools:<br><br>- `days_of_week`                         - (Required) Set: Monday..Sunday<br>- `ramp_up_start_time`                   - (Required) "HH:MM"<br>- `ramp_up_load_balancing_algorithm`     - (Required) BreadthFirst \| DepthFirst<br>- `ramp_up_minimum_hosts_percent`        - (Optional) 0-100  (Azure default applies when omitted)<br>- `ramp_up_capacity_threshold_percent`   - (Optional) 1-100  (Azure default applies when omitted)<br>- `peak_start_time`                      - (Required) "HH:MM"<br>- `peak_load_balancing_algorithm`        - (Required) BreadthFirst \| DepthFirst<br>- `ramp_down_start_time`                 - (Required) "HH:MM"<br>- `ramp_down_load_balancing_algorithm`   - (Required) BreadthFirst \| DepthFirst<br>- `ramp_down_minimum_hosts_percent`      - (Required) 0-100<br>- `ramp_down_capacity_threshold_percent` - (Required) 1-100<br>- `ramp_down_force_logoff_users`         - (Required) bool<br>- `ramp_down_wait_time_minutes`          - (Required) minutes before forced logoff<br>- `ramp_down_notification_message`       - (Required) shown to users before logoff<br>- `ramp_down_stop_hosts_when`            - (Required) ZeroActiveSessions \| ZeroSessions<br>- `off_peak_start_time`                  - (Required) "HH:MM"<br>- `off_peak_load_balancing_algorithm`    - (Required) BreadthFirst \| DepthFirst | <pre>map(object({<br>    days_of_week                         = set(string)<br>    ramp_up_start_time                   = string<br>    ramp_up_load_balancing_algorithm     = string<br>    ramp_up_minimum_hosts_percent        = optional(number)<br>    ramp_up_capacity_threshold_percent   = optional(number)<br>    peak_start_time                      = string<br>    peak_load_balancing_algorithm        = string<br>    ramp_down_start_time                 = string<br>    ramp_down_load_balancing_algorithm   = string<br>    ramp_down_minimum_hosts_percent      = number<br>    ramp_down_capacity_threshold_percent = number<br>    ramp_down_force_logoff_users         = bool<br>    ramp_down_wait_time_minutes          = number<br>    ramp_down_notification_message       = string<br>    ramp_down_stop_hosts_when            = string<br>    off_peak_start_time                  = string<br>    off_peak_load_balancing_algorithm    = string<br>  }))</pre> | n/a | yes |
| description | n/a | `string` | `null` | no |
| environment | n/a | `string` | `null` | no |
| exclusion\_tag | Tag name on session hosts to exclude from autoscale (e.g. 'excludeFromScaling'). | `string` | `null` | no |
| friendly\_name | n/a | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the scaling plan. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit scaling plan name. If null, computed automatically. | `string` | `null` | no |
| region\_code | n/a | `string` | `null` | no |
| role\_assignments | Map of role assignments at the scaling plan scope. Useful for AVD admin contributor visibility scenarios. Default principal\_type='Group'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "Group")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | n/a | `string` | `null` | no |
| tags | ############################################################## TAGS ############################################################## F-7: nullable = false added (merge(null, ...) would panic). | `map(string)` | `{}` | no |
| time\_zone | Windows time zone name (e.g. 'W. Europe Standard Time', 'Romance Standard Time'). IANA names are not accepted by the Azure API. | `string` | `"W. Europe Standard Time"` | no |
| workload | Workload suffix (e.g. pooled). | `string` | `"pooled"` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Scaling plan resource ID |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | Scaling plan name |
| resource | Full scaling plan resource object |
| role\_assignment\_ids | Map of role assignment logical name => role assignment ID |
<!-- END_TF_DOCS -->
