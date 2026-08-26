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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| application\_group | ../AvdApplicationGroup | n/a |
| host\_pool | ../AvdHostPool | n/a |
| scaling\_plan | ../AvdScalingPlan | n/a |
| session\_host | ../AvdSessionHost | n/a |
| workspace | ../AvdWorkspace | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment (e.g. nprd, prod). | `string` | n/a | yes |
| location | Azure region of the AVD control plane. AVD metadata objects are region-bound; session hosts may live elsewhere. | `string` | n/a | yes |
| region\_code | Region code of the AVD CONTROL PLANE (host pool/workspace/app groups/scaling plan), e.g. weu. | `string` | n/a | yes |
| resource\_group\_name | Existing resource group for the AVD control-plane objects (host pool, app groups, workspace, scaling plan). | `string` | n/a | yes |
| subscription\_acronym | Subscription acronym (e.g. avd). | `string` | n/a | yes |
| application\_groups | Map of application groups. Key = logical name (also the naming workload unless overridden, and the workspace association key). Desktop or RemoteApp. Assign 'Desktop Virtualization User' to end-user groups via role\_assignments. | <pre>map(object({<br>    type                         = optional(string, "Desktop")<br>    workload                     = optional(string)<br>    friendly_name                = optional(string)<br>    description                  = optional(string)<br>    default_desktop_display_name = optional(string)<br>    applications = optional(map(object({<br>      name                         = string<br>      path                         = string<br>      command_line_argument_policy = string<br>      friendly_name                = optional(string)<br>      description                  = optional(string)<br>      command_line_arguments       = optional(string)<br>      icon_path                    = optional(string)<br>      icon_index                   = optional(number, 0)<br>      show_in_portal               = optional(bool, true)<br>    })), {})<br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name       = string<br>      principal_id                     = string<br>      principal_type                   = optional(string, "Group")<br>      condition                        = optional(string)<br>      condition_version                = optional(string)<br>      description                      = optional(string)<br>      skip_service_principal_aad_check = optional(bool, false)<br>    })), {})<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br>  }))</pre> | <pre>{<br>  "desktop": {<br>    "type": "Desktop"<br>  }<br>}</pre> | no |
| host\_pool | Host pool configuration. A registration token is always created (create\_registration\_info = true) so the session hosts can join. | <pre>object({<br>    workload                      = optional(string)<br>    type                          = optional(string, "Pooled")<br>    load_balancer_type            = optional(string, "BreadthFirst")<br>    maximum_sessions_allowed      = optional(number, 8)<br>    preferred_app_group_type      = optional(string, "Desktop")<br>    start_vm_on_connect           = optional(bool, true)<br>    public_network_access         = optional(string, "Disabled")<br>    custom_rdp_properties         = optional(string)<br>    friendly_name                 = optional(string)<br>    description                   = optional(string)<br>    registration_expiration_hours = optional(number, 48)<br>    scheduled_agent_updates = optional(object({<br>      enabled                   = optional(bool, false)<br>      timezone                  = optional(string)<br>      use_session_host_timezone = optional(bool, false)<br>      schedule = optional(list(object({<br>        day_of_week = string<br>        hour_of_day = number<br>      })), [])<br>    }))<br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name       = string<br>      principal_id                     = string<br>      principal_type                   = optional(string, "Group")<br>      condition                        = optional(string)<br>      condition_version                = optional(string)<br>      description                      = optional(string)<br>      skip_service_principal_aad_check = optional(bool, false)<br>    })), {})<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br>  })</pre> | `{}` | no |
| scaling\_plan | Optional autoscale plan bound to the host pool. Null = no scaling plan. schedules is required when set. | <pre>object({<br>    workload      = optional(string, "pooled")<br>    time_zone     = optional(string, "W. Europe Standard Time")<br>    friendly_name = optional(string)<br>    description   = optional(string)<br>    exclusion_tag = optional(string)<br>    enabled       = optional(bool, true) # scaling_plan_enabled on the host pool association<br>    schedules = map(object({<br>      days_of_week                         = set(string)<br>      ramp_up_start_time                   = string<br>      ramp_up_load_balancing_algorithm     = string<br>      ramp_up_minimum_hosts_percent        = optional(number)<br>      ramp_up_capacity_threshold_percent   = optional(number)<br>      peak_start_time                      = string<br>      peak_load_balancing_algorithm        = string<br>      ramp_down_start_time                 = string<br>      ramp_down_load_balancing_algorithm   = string<br>      ramp_down_minimum_hosts_percent      = number<br>      ramp_down_capacity_threshold_percent = number<br>      ramp_down_force_logoff_users         = bool<br>      ramp_down_wait_time_minutes          = number<br>      ramp_down_notification_message       = string<br>      ramp_down_stop_hosts_when            = string<br>      off_peak_start_time                  = string<br>      off_peak_load_balancing_algorithm    = string<br>    }))<br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name       = string<br>      principal_id                     = string<br>      principal_type                   = optional(string, "Group")<br>      condition                        = optional(string)<br>      condition_version                = optional(string)<br>      description                      = optional(string)<br>      skip_service_principal_aad_check = optional(bool, false)<br>    })), {})<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br>  })</pre> | `null` | no |
| session\_host | Session host configuration. Null = deploy the control plane only (add hosts later). When set, subnet\_id, admin\_password\_kv\_id and fslogix\_vhd\_location are required. Override resource\_group\_name/location/region\_code to place hosts in a different (e.g. gwc) RG/region than the control plane. | <pre>object({<br>    # Placement overrides (default to the control-plane RG/region).<br>    resource_group_name = optional(string)<br>    location            = optional(string)<br>    region_code         = optional(string)<br>    workload            = optional(string, "sh")<br><br>    # Required.<br>    subnet_id            = string<br>    admin_password_kv_id = string<br>    fslogix_vhd_location = string<br><br>    # VM sizing / image.<br>    vm_count                       = optional(number, 1)<br>    vm_size                        = optional(string, "Standard_D4s_v5")<br>    availability_zones             = optional(list(string), ["1", "2", "3"])<br>    accelerated_networking_enabled = optional(bool, true)<br>    image = optional(object({<br>      publisher = string<br>      offer     = string<br>      sku       = string<br>      version   = optional(string, "latest")<br>      }), {<br>      publisher = "microsoftwindowsdesktop"<br>      offer     = "windows-11"<br>      sku       = "win11-24h2-avd"<br>      version   = "latest"<br>    })<br>    image_plan = optional(object({<br>      name      = string<br>      publisher = string<br>      product   = string<br>    }))<br>    source_image_id = optional(string)<br>    os_disk = optional(object({<br>      storage_account_type = optional(string, "Premium_LRS")<br>      caching              = optional(string, "ReadWrite")<br>      disk_size_gb         = optional(number, 128)<br>      ephemeral            = optional(bool, true)<br>    }), {})<br><br>    # Identity / OS.<br>    admin_username             = optional(string, "azureadmin")<br>    admin_password_secret_name = optional(string, "sh-local-admin-password")<br>    computer_name_prefix       = optional(string)<br>    enable_trusted_launch      = optional(bool, true)<br>    encryption_at_host_enabled = optional(bool, true)<br>    license_type               = optional(string, "Windows_Client")<br>    patch_mode                 = optional(string, "AutomaticByPlatform")<br>    fslogix_profile_size_mb    = optional(number, 30000)<br><br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name       = string<br>      principal_id                     = string<br>      principal_type                   = optional(string, "Group")<br>      condition                        = optional(string)<br>      condition_version                = optional(string)<br>      description                      = optional(string)<br>      skip_service_principal_aad_check = optional(bool, false)<br>    })), {})<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br>  })</pre> | `null` | no |
| tags | Tags applied to every resource in the stack. | `map(string)` | `{}` | no |
| workload | Workload suffix for the control-plane objects (host pool, workspace, scaling plan) unless overridden per component. | `string` | `"avd"` | no |
| workspace | Workspace configuration. All application\_groups are associated to it automatically. | <pre>object({<br>    workload                      = optional(string)<br>    friendly_name                 = optional(string)<br>    description                   = optional(string)<br>    public_network_access_enabled = optional(bool, false)<br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name       = string<br>      principal_id                     = string<br>      principal_type                   = optional(string, "Group")<br>      condition                        = optional(string)<br>      condition_version                = optional(string)<br>      description                      = optional(string)<br>      skip_service_principal_aad_check = optional(bool, false)<br>    })), {})<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| application\_group\_ids | Map of application group key => resource ID. |
| application\_group\_names | Map of application group key => name. |
| host\_pool\_id | Host pool resource ID. |
| host\_pool\_name | Host pool name. |
| host\_pool\_registration\_token | Host pool registration token (sensitive). |
| scaling\_plan\_id | Scaling plan resource ID, or null when no scaling plan was created. |
| session\_host\_vm\_ids | Map of session host VM index => VM ID, or null when no session hosts were created. |
| session\_host\_vm\_names | Map of session host VM index => VM name, or null when no session hosts were created. |
| workspace\_id | Workspace resource ID. |
| workspace\_name | Workspace name. |
<!-- END_TF_DOCS -->
