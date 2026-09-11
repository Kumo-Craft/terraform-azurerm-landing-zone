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
