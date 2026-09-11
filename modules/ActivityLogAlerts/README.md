# ActivityLogAlerts

Map-driven Azure Monitor **activity-log alerts** (`azurerm_monitor_activity_log_alert`) on a subscription. First use case: **Service Health** (incidents, planned maintenance, service deprecations) — Azure Advisor flags the absence of a Service Health alert as **High**.

Modeled on [`LogAnalyticsAlerts`](../LogAnalyticsAlerts): one `alerts = { key = {...} }` map, each alert named `{base}-{key}` → e.g. `ala-pgs-prod-gwc-servicehealth-incidents`.

## Usage

```hcl
module "activity_log_alerts" {
  source = "../ActivityLogAlerts"

  subscription_acronym = "pgs"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "servicehealth"
  resource_group_name  = "rg-pgs-prod-gwc-monitoring"

  scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  action_group_ids = [dependency.ag.outputs.id]

  alerts = {
    incidents = {
      category       = "ServiceHealth"
      description    = "Azure service incidents affecting the subscription"
      service_health = { events = ["Incident"] }
    }
    maintenance = {
      category       = "ServiceHealth"
      service_health = { events = ["Maintenance"] }
    }
  }
}
```

## ⚠️ Gotchas (read before consuming)

- **`location` is always `global` — the module hardcodes it.** The provider requires `location`, but Azure accepts only `global` / `westeurope` / `northeurope` / `eastus2euap` for this resource type — **not** the caller's region, so a `germanywestcentral` **passes the plan but fails at apply**. **Service Health** alert rules in particular *must* be `global`, so the module standardizes on `global` and does not expose `location`. `region_code` here is for the *name* only. (`westeurope`/`northeurope` are EU-Data-Boundary processing options for non-ServiceHealth categories — a possible future opt-in, out of scope today.)
- **These alerts are stateless — they never auto-resolve.** An activity log alert fires on an event and stays **"Fired"** indefinitely; there is no monitor-condition that clears. This is expected Azure behaviour — don't open tickets asking why the alert "doesn't close". Manage state via the Action Group / downstream tooling, not the alert.
- **`scopes`** = the resource IDs whose activity-log events are evaluated (typically the subscription ID).
- **Sub-block ↔ category coupling** (enforced by validators): `service_health` requires `category = "ServiceHealth"`; `resource_health` requires `category = "ResourceHealth"`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional explicit base name (else ala-{sub}-{env}-{region}-{workload}). | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components. | `string` | see vars | Conditional |
| resource_group_name | RG holding the alerts. | `string` | -- | Yes |
| scopes | Scopes whose activity-log events are evaluated (usually the subscription ID). | `list(string)` | -- | Yes |
| action_group_ids | Action Group IDs notified by every alert. | `list(string)` | -- | Yes |
| alerts | Map of alerts `{ category, description, enabled, service_health, resource_health }`. | `map(object)` | -- | Yes |
| lock | Optional resource lock (CanNotDelete / ReadOnly), applied per alert. | `object` | `null` | No |
| tags | Tags to apply. | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of alert key => alert ID |
| names | Map of alert key => full name ({base}-{key}) |
| resources | Map of alert key => resource object |
| lock_ids | Map of alert key => lock ID ({} if no lock) |

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

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_activity_log_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| action\_group\_ids | Action Group IDs notified by EVERY alert in var.alerts. | `list(string)` | n/a | yes |
| alerts | Map of activity-log alerts. Key becomes the name suffix ({base}-{key}).<br><br>Per entry:<br>- `category`        - (Required) Activity log category: Administrative, ServiceHealth,<br>                      ResourceHealth, Alert, Autoscale, Security, Recommendation, Policy.<br>- `description`     - (Optional) Alert description.<br>- `enabled`         - (Optional) Default true.<br>- `service_health`  - (Optional) Only with category = ServiceHealth. Filter by<br>                      events / locations / services (lists; empty/null = all).<br>                      events ∈ Incident \| Maintenance \| Informational \|<br>                      ActionRequired \| Security. (Values are documented, not<br>                      hard-validated — a typo surfaces as an ARM 400 at apply.)<br>- `resource_health` - (Optional) Only with category = ResourceHealth. Filter by<br>                      current / previous / reason (lists). current/previous ∈<br>                      Available \| Degraded \| Unavailable \| Unknown; reason ∈<br>                      PlatformInitiated \| UserInitiated \| Unknown. | <pre>map(object({<br>    category    = string<br>    description = optional(string)<br>    enabled     = optional(bool, true)<br>    service_health = optional(object({<br>      events    = optional(list(string))<br>      locations = optional(list(string))<br>      services  = optional(list(string))<br>    }))<br>    resource_health = optional(object({<br>      current  = optional(list(string))<br>      previous = optional(list(string))<br>      reason   = optional(list(string))<br>    }))<br>  }))</pre> | n/a | yes |
| resource\_group\_name | Resource group that holds the alert resources. | `string` | n/a | yes |
| scopes | Scopes the alerts watch — typically the subscription ID. Activity log events raised under these scopes are evaluated. | `list(string)` | n/a | yes |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) applied to every alert. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Optional. Explicit base name. If null, computed (ala-{sub}-{env}-{region}-{workload}); each alert is named {base}-{key}. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, frc). NOTE: this is for NAMING only — the alert resource itself is always 'global' (see main.tf). | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. pgs, mgm) | `string` | `null` | no |
| tags | Tags to apply to every alert. | `map(string)` | `{}` | no |
| workload | Workload suffix (e.g. servicehealth, 01) | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of alert key => activity log alert ID. |
| lock\_ids | Map of alert key => management lock ID ({} if var.lock is null). |
| names | Map of alert key => full resource name ({base}-{key}). |
| resources | Map of alert key => complete resource object. |
<!-- END_TF_DOCS -->
