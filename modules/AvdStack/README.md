# AvdStack

Composite module that stands up a **complete AVD deployment** by wiring the `Avd*` leaf submodules together:

```
AvdHostPool (registration token) ──► AvdSessionHost (join)
        │                             (optional; own RG/region)
        ├──► AvdApplicationGroup[*] ──► AvdWorkspace (associations)
        └──► AvdScalingPlan (optional)
```

It **consumes existing resource groups** (repo convention — it never creates RGs): one for the control plane and, optionally, another for the session hosts. Everything else — Key Vault (admin password), subnet, FSLogix share, gallery image — is referenced by ID and lives in its own RG.

## What it creates

| Component | Always? | Placement |
|---|---|---|
| Host pool (+ registration token) | ✅ | control-plane RG/region |
| Application group(s) (map, default 1× Desktop) | ✅ | control-plane RG/region |
| Workspace (+ associations to all app groups) | ✅ | control-plane RG/region |
| Scaling plan | when `scaling_plan != null` | control-plane RG/region |
| Session hosts | when `session_host != null` | `session_host` RG/region (override) |

## Usage

```hcl
module "avd" {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/AvdStack?ref=v0.5.0"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "weu"                    # control plane region
  location             = "westeurope"
  resource_group_name  = "rg-avd-nprd-weu-avd"    # control-plane RG

  # End-user entitlement on the desktop app group
  application_groups = {
    desktop = {
      type          = "Desktop"
      friendly_name = "Bureau AVD"
      role_assignments = {
        users = {
          role_definition_id_or_name = "Desktop Virtualization User"
          principal_id               = "<aad-group-object-id>"
        }
      }
    }
  }

  # Autoscale (optional)
  scaling_plan = {
    schedules = {
      weekday = {
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "BreadthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 10
        ramp_down_capacity_threshold_percent = 90
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "Vous allez être déconnecté."
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    }
  }

  # Session hosts — placed in a DIFFERENT RG/region (gwc) than the control plane (weu)
  session_host = {
    resource_group_name  = "rg-avd-nprd-gwc-sh"
    location             = "germanywestcentral"
    region_code          = "gwc"
    subnet_id            = "/subscriptions/.../rg-avd-nprd-gwc-network/.../subnets/snet-sh"
    admin_password_kv_id = "/subscriptions/.../rg-avd-nprd-gwc-kv/.../vaults/kv-avd-nprd-gwc"
    fslogix_vhd_location = "\\\\stavdfslogix.file.core.windows.net\\profiles"
    vm_count             = 2

    # Build from a golden gallery image (see ComputeGallery / AvdImageTemplate)
    source_image_id = "${module.compute_gallery.image_definition_id}/versions/1.0.3"
  }

  tags = { Environment = "Non Production" }
}
```

### Control-plane only (add hosts later)

Leave `session_host = null` (default). The host pool, app groups and workspace are created; register session hosts later via a separate [`AvdSessionHost`](../AvdSessionHost/) call using `host_pool_registration_token`.

### Multiple application groups (Desktop + RemoteApp)

```hcl
application_groups = {
  desktop = { type = "Desktop", friendly_name = "Bureau" }
  apps = {
    type = "RemoteApp"
    applications = {
      code = { name = "VSCode", path = "C:\\Program Files\\Microsoft VS Code\\Code.exe", command_line_argument_policy = "DoNotAllow" }
    }
  }
}
```

All app groups are associated to the workspace automatically (association key = map key).

## Split RG / region

AVD metadata objects (host pool, workspace, app groups, scaling plan) are region-bound and live in the control-plane RG (`resource_group_name` / `location` / `region_code`). Session hosts commonly live elsewhere — set `session_host.resource_group_name` / `location` / `region_code` to place the VMs in e.g. a `gwc` RG while the control plane stays in `weu`. Each override defaults to the control-plane value when omitted.

## Naming

Each leaf module applies its own type prefix via `../Naming`; the stack just forwards `subscription_acronym` / `environment` / `region_code` / `workload`:

| Resource | Name |
|---|---|
| Host pool | `vdpool-{acr}-{env}-{region}-{workload}` |
| Workspace | `vdws-{acr}-{env}-{region}-{workload}` |
| Application group | `vdag-{acr}-{env}-{region}-{key}` (map key = workload unless overridden) |
| Scaling plan | `vdscaling-{acr}-{env}-{region}-{scaling_plan.workload}` |
| Session host VMs | `vm-{acr}-{env}-{session region}-{sh workload}-{NN}` |

## Key Inputs

| Name | Default | Description |
|---|---|---|
| `subscription_acronym` / `environment` / `region_code` / `location` | — | Shared naming + control-plane region |
| `resource_group_name` | — | Existing control-plane RG |
| `workload` | `"avd"` | Control-plane naming suffix |
| `host_pool` | `{}` | Host pool knobs (type, load balancer, sessions, RDP props, agent updates, RBAC, lock). Token always created |
| `application_groups` | `{ desktop = { type = "Desktop" } }` | Map of app groups (Desktop/RemoteApp), each with optional RBAC + apps |
| `workspace` | `{}` | Workspace knobs (friendly name, public access = false, RBAC, lock) |
| `scaling_plan` | `null` | Autoscale plan (schedules required when set) |
| `session_host` | `null` | Session host config (subnet/KV/FSLogix required; RG/region overrides; image or `source_image_id`) |
| `tags` | `{}` | Applied to every resource |

## Outputs

| Name | Description |
|---|---|
| `host_pool_id` / `host_pool_name` | Host pool |
| `host_pool_registration_token` | Sensitive — for out-of-band session host registration |
| `application_group_ids` / `application_group_names` | Maps keyed by app group key |
| `workspace_id` / `workspace_name` | Workspace |
| `scaling_plan_id` | Scaling plan ID, or `null` |
| `session_host_vm_ids` / `session_host_vm_names` | Maps keyed by VM index, or `null` |

## Notes

- **Secure defaults inherited** from the leaves: host pool `public_network_access = Disabled`, workspace `public_network_access_enabled = false` (wire a feed Private Endpoint), session hosts Trusted Launch + host encryption on. Pair with [`PrivateEndpoint`](../PrivateEndpoint/) for the workspace `feed` / host pool `connection` sub-resources.
- **Golden image chain.** Build images with [`AvdImageTemplate`](../AvdImageTemplate/) → [`ComputeGallery`](../ComputeGallery/), then feed `session_host.source_image_id`.
- For per-resource deep control beyond what the nested objects expose, use the [`Avd*`](../) leaf modules directly.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |
