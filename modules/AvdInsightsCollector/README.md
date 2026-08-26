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
| [azurerm_monitor_data_collection_rule.avd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_data_collection_rule_association.avd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region for the DCR (must match the session hosts' region). | `string` | n/a | yes |
| log\_analytics\_workspace\_id | Resource ID of the Log Analytics Workspace the AVD Insights data is shipped to (compose ../LogAnalyticsWorkspace). This module does NOT create a workspace. | `string` | n/a | yes |
| resource\_group\_name | Resource group hosting the DCR. | `string` | n/a | yes |
| environment | Environment (e.g. prod, nprd). | `string` | `null` | no |
| lock | Optional Resource Lock on the DCR.<br><br>Note: this module deliberately carries NO hardcoded lifecycle.prevent\_destroy<br>— a hardcoded guard has blocked legitimate destroys before (cf. Ampls). Use<br>this variable when you want a delete guard.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Explicit DCR name override (escape hatch). If null, derived via ../Naming (dcr-{acr}-{env}-{region}-{workload}-avdinsights). | `string` | `null` | no |
| performance\_counters | Performance counters shipped to the Perf table (stream Microsoft-Perf).<br>Defaults to the 20 counters AVD Insights reads, at Microsoft's documented<br>sampling frequencies (two blocks because the frequencies differ):<br>  - 30s: 15 counters (disk queues, memory, processor, input delay, RemoteFX)<br>  - 60s: 5 counters (free space, disk sec/transfer, Terminal Services sessions)<br>Source: https://learn.microsoft.com/azure/virtual-desktop/insights-costs<br>Override to trim cost or add counters. | <pre>list(object({<br>    name                          = string<br>    sampling_frequency_in_seconds = number<br>    counter_specifiers            = list(string)<br>  }))</pre> | <pre>[<br>  {<br>    "counter_specifiers": [<br>      "\\LogicalDisk(C:)\\Avg. Disk Queue Length",<br>      "\\LogicalDisk(C:)\\Current Disk Queue Length",<br>      "\\Memory(*)\\Available Mbytes",<br>      "\\Memory(*)\\Page Faults/sec",<br>      "\\Memory(*)\\Pages/sec",<br>      "\\Memory(*)\\% Committed Bytes In Use",<br>      "\\PhysicalDisk(*)\\Avg. Disk Queue Length",<br>      "\\PhysicalDisk(*)\\Avg. Disk sec/Read",<br>      "\\PhysicalDisk(*)\\Avg. Disk sec/Transfer",<br>      "\\PhysicalDisk(*)\\Avg. Disk sec/Write",<br>      "\\Processor Information(_Total)\\% Processor Time",<br>      "\\User Input Delay per Process(*)\\Max Input Delay",<br>      "\\User Input Delay per Session(*)\\Max Input Delay",<br>      "\\RemoteFX Network(*)\\Current TCP RTT",<br>      "\\RemoteFX Network(*)\\Current UDP Bandwidth"<br>    ],<br>    "name": "avd-perf-30s",<br>    "sampling_frequency_in_seconds": 30<br>  },<br>  {<br>    "counter_specifiers": [<br>      "\\LogicalDisk(C:)\\% Free Space",<br>      "\\LogicalDisk(C:)\\Avg. Disk sec/Transfer",<br>      "\\Terminal Services(*)\\Active Sessions",<br>      "\\Terminal Services(*)\\Inactive Sessions",<br>      "\\Terminal Services(*)\\Total Sessions"<br>    ],<br>    "name": "avd-perf-60s",<br>    "sampling_frequency_in_seconds": 60<br>  }<br>]</pre> | no |
| region\_code | Region code (e.g. gwc, weu). | `string` | `null` | no |
| session\_host\_ids | Resource IDs of the AVD session host VMs to associate with the DCR.<br><br>Defaults to [] on purpose: the DCR must be creatable BEFORE the session<br>hosts exist (the host pool build consumes the workspace/DCR), so the usual<br>flow is — apply once with [] to create the DCR, then a second apply once<br>the hosts are up to create the associations. Passing unknown-at-plan host<br>ids here would otherwise force a for\_each on unknown keys. | `list(string)` | `[]` | no |
| subscription\_acronym | Subscription acronym (e.g. avd, shc, mgm). | `string` | `null` | no |
| tags | Tags to apply to the DCR. | `map(string)` | `{}` | no |
| windows\_event\_logs | Windows event logs shipped to the Event table (stream Microsoft-Event).<br>Defaults to the 6 logs AVD Insights reads.<br><br>LEVEL CAVEAT: Microsoft documents the log NAMES but not the workbook's exact<br>levels — the levels below are a deliberate cost trade-off, hence this override:<br>  - Application / System        -> Critical+Error+Warning only (Level 1,2,3).<br>    High volume; Information carries no diagnostic value for AVD here.<br>  - FSLogix x2 / TerminalServices x2 -> + Information (Level 1,2,3,4,0).<br>    Low volume, and exactly where profile/session failures are diagnosed.<br>Windows levels: 0=LogAlways, 1=Critical, 2=Error, 3=Warning, 4=Information. | <pre>list(object({<br>    name           = string<br>    x_path_queries = list(string)<br>  }))</pre> | <pre>[<br>  {<br>    "name": "avd-eventlogs",<br>    "x_path_queries": [<br>      "Application!*[System[(Level=1 or Level=2 or Level=3)]]",<br>      "System!*[System[(Level=1 or Level=2 or Level=3)]]",<br>      "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",<br>      "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",<br>      "Microsoft-FSLogix-Apps/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",<br>      "Microsoft-FSLogix-Apps/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]"<br>    ]<br>  }<br>]</pre> | no |
| workload | Workload suffix in the DCR/DCRA names (the -avdinsights component is appended after it). | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| association\_ids | Map of session host resource ID => DCR association ID (empty until session\_host\_ids is populated). |
| id | Resource ID of the AVD Insights Data Collection Rule. |
| lock\_ids | Map of management lock IDs (empty when var.lock is null). |
| name | Name of the AVD Insights Data Collection Rule. |
<!-- END_TF_DOCS -->
