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
