# PrometheusAlertRules

Creates AMBA-style Managed Prometheus alert rule groups for AKS clusters backed by an Azure Monitor Workspace. Supports multiple named rule groups (each up to 20 alerts, Azure hard limit), per-alert severity (0..4), configurable alert resolution, and optional resource locks.

## Breaking changes (v0.2.43)

### `var.action_group_id` REMOVED (I-1)

The scalar `action_group_id` variable has been removed. Use `action_group_ids` (list) instead.

| Before | After |
|---|---|
| `action_group_id = "/subscriptions/.../actionGroups/ag-01"` | `action_group_ids = ["/subscriptions/.../actionGroups/ag-01"]` |
| `action_group_id = X` + `action_group_ids = [A, B]` | `action_group_ids = [X, A, B]` |

## Usage

### Standalone — AMW-only scope (no AKS)

```hcl
module "prometheus_alert_rules" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/PrometheusAlertRules?ref=v0.2.43"

  location            = "germanywestcentral"
  resource_group_name = "rg-mgm-prod-gwc-monitor"
  monitor_workspace_id = "/subscriptions/.../accounts/amw-mgm-prod-gwc-01"

  action_group_ids = [
    "/subscriptions/.../actionGroups/ag-mgm-prod-gwc-alerts"
  ]

  rule_groups = {
    "node-cpu" = {
      interval = "PT1M"
      alerts = {
        "NodeCPUHigh" = {
          expression = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 90"
          severity   = 2
          for        = "PT5M"
        }
      }
    }
  }

  tags = { Environment = "Production" }
}
```

### Standalone — AKS-scoped

```hcl
module "prometheus_alert_rules" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/PrometheusAlertRules?ref=v0.2.43"

  location            = "germanywestcentral"
  resource_group_name = "rg-api-prod-gwc-aks"
  monitor_workspace_id = "/subscriptions/.../accounts/amw-mgm-prod-gwc-01"
  aks_cluster_id      = "/subscriptions/.../managedClusters/aks-api-prod-gwc"
  aks_cluster_name    = "aks-api-prod-gwc"

  action_group_ids = [
    "/subscriptions/.../actionGroups/ag-api-prod-gwc-aks"
  ]

  lock = { kind = "CanNotDelete" }

  rule_groups = {
    "node-cpu" = {
      interval = "PT1M"
      alerts = {
        "NodeCPUHigh" = {
          expression = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 90"
          severity   = 2
          for        = "PT5M"
        }
      }
    }
    "pod-restarts" = {
      interval = "PT5M"
      alerts = {
        "PodRestartHigh" = {
          expression = "rate(kube_pod_container_status_restarts_total[15m]) > 0"
          severity   = 3
          alert_resolution = {
            auto_resolved   = true
            time_to_resolve = "PT30M"
          }
        }
      }
    }
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PrometheusAlertRules"
}

inputs = {
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  monitor_workspace_id = dependency.amw.outputs.id
  aks_cluster_id       = dependency.aks.outputs.id
  aks_cluster_name     = dependency.aks.outputs.name
  action_group_ids     = [dependency.ag.outputs.id]
  rule_groups          = local.rule_groups
  tags                 = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group for the alert rule groups | `string` | -- | Yes |
| monitor_workspace_id | Azure Monitor Workspace ID (Prometheus scope) | `string` | -- | Yes |
| action_group_ids | List of Action Group ARM IDs (1..5, Azure limit) | `list(string)` | -- | Yes |
| rule_groups | Map of alert rule groups (see below) | `map(object)` | -- | Yes |
| aks_cluster_id | AKS cluster resource ID (null for AMW-only scope) | `string` | `null` | No |
| aks_cluster_name | AKS cluster name (null for AMW-only scope; must pair with aks_cluster_id) | `string` | `null` | No |
| lock | Resource lock config `{ kind, name? }` (null = no lock) | `object` | `null` | No |
| subscription_acronym | Subscription acronym — optional, for metadata consistency | `string` | `null` | No |
| environment | Environment code — optional, for metadata consistency | `string` | `null` | No |
| region_code | Region code — optional, for metadata consistency | `string` | `null` | No |
| workload | Workload suffix | `string` | `"aks-alerts"` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

### `rule_groups` map shape

```hcl
rule_groups = {
  "<group-key>" = {
    interval = "PT1M"   # ISO 8601, PT1M..PT20M (Azure limit)
    enabled  = true
    alerts = {
      "<alert-name>" = {
        expression  = "<PromQL>"
        for         = "PT15M"   # ISO 8601 duration, optional
        severity    = 3         # 0 (critical) .. 4 (verbose)
        enabled     = true
        labels      = {}
        annotations = {}
        alert_resolution = {     # optional, defaults shown
          auto_resolved   = true
          time_to_resolve = "PT15M"
        }
      }
    }
  }
}
```

Resource names follow the pattern:
- AKS-scoped: `<group-key>-<aks_cluster_name>` (e.g. `node-cpu-aks-api-prod-gwc`)
- AMW-only: `<group-key>` (e.g. `node-cpu`)

Note: Resource names are semantically driven by group key and cluster name rather than the standard house naming pattern, because alert groups must be uniquely and meaningfully named per-alert and per-cluster. Standard naming vars (`subscription_acronym`, `environment`, `region_code`) are accepted for tracking/audit metadata consistency only.

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of rule group key => resource ID |
| names | Map of rule group key => resource name |
| rule_groups | Map of rule group key => full resource object |
| lock_ids | Map of rule group key => management lock ID (empty map when var.lock is null) |

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

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_alert_prometheus_rule_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_alert_prometheus_rule_group) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| action\_group\_ids | List of Action Group resource IDs to wire to every alert in this rule group. At least 1 required (Azure requires actions on alert rules). Maximum 5 (Azure limit). | `list(string)` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| monitor\_workspace\_id | ID of the Azure Monitor Workspace (Prometheus scope) | `string` | n/a | yes |
| resource\_group\_name | Resource group for the alert rule groups | `string` | n/a | yes |
| rule\_groups | Map of Prometheus alert rule groups. Key = group name suffix. Max 20 rules per group (Azure limit). severity must be 0..4. | <pre>map(object({<br>    interval = optional(string, "PT1M")<br>    enabled  = optional(bool, true)<br>    alerts = map(object({<br>      expression  = string<br>      for         = optional(string, "PT15M")<br>      severity    = optional(number, 3)<br>      enabled     = optional(bool, true)<br>      labels      = optional(map(string), {})<br>      annotations = optional(map(string), {})<br>      # M-5: per-alert alert_resolution override.<br>      alert_resolution = optional(object({<br>        auto_resolved   = optional(bool, true)<br>        time_to_resolve = optional(string, "PT15M")<br>      }), { auto_resolved = true, time_to_resolve = "PT15M" })<br>    }))<br>  }))</pre> | n/a | yes |
| aks\_cluster\_id | ID of the AKS cluster. Required when aks\_cluster\_name is set; both must be null for AMW-only scope. | `string` | `null` | no |
| aks\_cluster\_name | Name of the AKS cluster (used in alert rule group names and cluster\_name scope). Required when aks\_cluster\_id is set; both must be null for AMW-only scope. | `string` | `null` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on each alert rule group. Applies to all groups in var.rule\_groups. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Unused override placeholder (naming vars are optional — resource names are semantically derived from rule group keys and cluster name). Kept for house-convention metadata consistency. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload suffix | `string` | `"aks-alerts"` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of rule group key to resource ID |
| lock\_ids | Map of rule group key => management lock ID (empty map when var.lock is null) |
| names | Map of rule group key to resource name |
| rule\_groups | Map of alert rule group key => full resource object |
<!-- END_TF_DOCS -->
