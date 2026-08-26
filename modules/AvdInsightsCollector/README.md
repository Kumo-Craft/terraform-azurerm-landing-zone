# AvdInsightsCollector

Purpose-built **Data Collection Rule** for **Azure Virtual Desktop Insights** + its associations to the session hosts. Ships the performance counters and Windows event logs the AVD Insights workbook reads to a Log Analytics Workspace via AMA.

Sibling of [`ContainerInsightsCollector`](../ContainerInsightsCollector/) (same family: a purpose-built DCR that takes a LAW as input and creates DCR + associations).

> The **workspace is an input** — compose [`../LogAnalyticsWorkspace`](../LogAnalyticsWorkspace/) and pass its `id`. This module never creates a LAW.

## What it collects

| | Stream → table | Content |
|---|---|---|
| Performance counters | `Microsoft-Perf` → **Perf** | The 20 AVD Insights counters, at Microsoft's frequencies |
| Windows event logs | `Microsoft-Event` → **Event** | The 6 AVD Insights logs |

**Why `Microsoft-Perf` / `Microsoft-Event` and not `Microsoft-InsightsMetrics`**: the AVD Insights workbook reads the **Perf** and **Event** tables. `Microsoft-InsightsMetrics` feeds *VM* Insights, isn't read by AVD Insights — and the provider forces `sampling_frequency_in_seconds = 60` for it, which would break the 30s counters.

### Performance counters (`performance_counters`)

Two blocks because Microsoft's sampling frequencies differ ([insights-costs](https://learn.microsoft.com/azure/virtual-desktop/insights-costs)):

- **30s — 15 counters**: `LogicalDisk(C:)` queue lengths, `Memory` (available/page faults/pages/committed), `PhysicalDisk` (queue + sec/Read|Transfer|Write), `Processor Information(_Total)\% Processor Time`, `User Input Delay per Process|Session\Max Input Delay`, `RemoteFX Network\Current TCP RTT|UDP Bandwidth`.
- **60s — 5 counters**: `LogicalDisk(C:)\% Free Space`, `LogicalDisk(C:)\Avg. Disk sec/Transfer`, `Terminal Services(*)\Active|Inactive|Total Sessions`.

### Windows event logs (`windows_event_logs`)

The 6 logs: `Application`, `System`, `Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin`, `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`, `Microsoft-FSLogix-Apps/Operational`, `Microsoft-FSLogix-Apps/Admin`.

> ⚠️ **Levels are a deliberate cost trade-off, not Microsoft doctrine.** MS documents the log *names* but not the workbook's exact levels. Defaults here:
> - **Application / System** → Critical+Error+Warning only (`Level=1 or 2 or 3`) — high volume, Information carries no diagnostic value for AVD.
> - **FSLogix ×2 / TerminalServices ×2** → + Information (`Level=1 or 2 or 3 or 4 or 0`) — low volume, and exactly where profile/session failures are diagnosed.
>
> Override `windows_event_logs` to change this. Windows levels: `0`=LogAlways, `1`=Critical, `2`=Error, `3`=Warning, `4`=Information.

## Naming

Via the [`Naming`](../Naming/) submodule with `extra_suffix = ["avdinsights"]`: `dcr-{acr}-{env}-{region}-{workload}-avdinsights` → e.g. **`dcr-avd-prod-gwc-01-avdinsights`** (same shape as AlzManagement's `dcr-mgm-prod-gwc-01-vminsights`). Set `name` to override.

## Two-stage apply (session hosts)

`session_host_ids` defaults to **`[]`** on purpose: the DCR must be creatable **before** the session hosts exist (the host pool build consumes the workspace/DCR). Passing not-yet-known host ids would force a `for_each` over unknown keys.

1. **Apply #1** — DCR created, no associations.
2. **Apply #2** — once the hosts are up, pass their ids → one association per host.

## Usage

```hcl
module "avd_law" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/LogAnalyticsWorkspace?ref=v0.3.0"

  subscription_acronym = "avd"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  location             = "germanywestcentral"
  resource_group_name  = azurerm_resource_group.avd.name
}

module "avd_insights" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/AvdInsightsCollector?ref=v0.3.0"

  subscription_acronym = "avd"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"

  location            = "germanywestcentral"
  resource_group_name = azurerm_resource_group.avd.name

  log_analytics_workspace_id = module.avd_law.id

  # Apply #2 — once the hosts exist
  session_host_ids = [for vm in azurerm_windows_virtual_machine.host : vm.id]

  tags = { Environment = "Production" }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | DCR name override. Null = derived. |
| `subscription_acronym` / `environment` / `region_code` | `string` | `null` | Naming components (required unless `name` set). |
| `workload` | `string` | `"01"` | Workload segment (the `-avdinsights` component is appended after it). |
| `location` | `string` | — (required) | Azure region (must match the session hosts). |
| `resource_group_name` | `string` | — (required) | RG hosting the DCR. |
| `log_analytics_workspace_id` | `string` | — (required) | LAW resource ID (from `../LogAnalyticsWorkspace`). |
| `session_host_ids` | `list(string)` | `[]` | Session host VM ids to associate — see *Two-stage apply*. |
| `performance_counters` | `list(object)` | MS 20-counter set | Perf counters (`name`, `sampling_frequency_in_seconds`, `counter_specifiers`). |
| `windows_event_logs` | `list(object)` | MS 6-log set | Event logs (`name`, `x_path_queries`). |
| `lock` | `object({ kind, name })` | `null` | Optional CanNotDelete/ReadOnly lock. |
| `tags` | `map(string)` | `{}` | Tags (a `CreatedOn` tag is added). |

## Outputs

| Name | Description |
|------|-------------|
| `id` | DCR resource ID. |
| `name` | DCR name. |
| `association_ids` | Map of session host id → association id (empty until `session_host_ids` is populated). |
| `lock_ids` | Map of lock IDs (empty when `lock` is null). |

## Notes

- **No hardcoded `prevent_destroy`** — a hardcoded guard has blocked a legitimate prod destroy before (cf. `Ampls`). Use `var.lock` when you want a delete guard.
- The **AMA extension** on the session hosts is out of scope (deploy it via policy/DINE or the VM extension) — this module only defines *what* to collect and *where* to ship it.

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: naming, `kind = Windows`, Perf/Event streams, the 15+5 counter split, the 6 event logs, associations per host, name override, lock, counter override, and validators (LAW id, empty counters/logs, sampling frequency bounds). Run: `terraform init -backend=false && terraform test`.
