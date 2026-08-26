# DiagnosticSettings

Creates Azure Monitor Diagnostic Settings on multiple Azure resources, forwarding log and metric categories to Log Analytics, Storage Account, Event Hub, or marketplace partners.

## Usage

### Standalone

```hcl
module "diagnostic_settings" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/DiagnosticSettings?ref=v0.2.48"

  diagnostic_settings = {
    vnet = {
      name                       = "diag-vnet"
      target_resource_id         = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"
      log_analytics_workspace_id = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01"
      logs                       = ["VMProtectionAlerts"]
      metrics                    = ["AllMetrics"]
    }
    nsg_nodes = {
      name                       = "diag-nsg-nodes"
      target_resource_id         = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-nodes"
      log_analytics_workspace_id = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01"
      logs                       = ["NetworkSecurityGroupEvent", "NetworkSecurityGroupRuleCounter"]
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/DiagnosticSettings"
}

inputs = {
  diagnostic_settings = {
    vnet = {
      name                       = "diag-vnet"
      target_resource_id         = dependency.vnet.outputs.id
      log_analytics_workspace_id = dependency.law.outputs.id
      logs                       = ["VMProtectionAlerts"]
      metrics                    = ["AllMetrics"]
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| diagnostic_settings | Map of Diagnostic Settings. Key is arbitrary. | `map(object({...}))` | -- | Yes |

### Diagnostic Setting Object

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| name | `string` | Yes | -- | Diagnostic setting name |
| target_resource_id | `string` | Yes | -- | Target Azure resource ID |
| logs | `list(string)` | No | `[]` | Per-category log names (e.g. `["kube-audit", "kube-apiserver"]`) |
| log_groups | `list(string)` | No | `[]` | Category-group names (e.g. `["allLogs", "audit"]`). Required for AKS audit-log capture and resources whose categories evolve. |
| metrics | `list(string)` | No | `[]` | Metric categories (typically `["AllMetrics"]`) |
| log_analytics_workspace_id | `string` | No | -- | Log Analytics Workspace ID |
| log_analytics_destination_type | `string` | No | -- | `Dedicated` (per-category tables, recommended) or `AzureDiagnostics` (legacy) |
| storage_account_id | `string` | No | -- | Storage Account ID for archival |
| event_hub_authorization_rule_id | `string` | No | -- | Event Hub auth rule ID |
| event_hub_name | `string` | No | -- | Event Hub name |
| marketplace_partner_resource_id | `string` | No | -- | Marketplace partner ID |

At least one destination must be set, **and** at least one of `logs` / `log_groups` / `metrics`.

> **Note — `log_analytics_destination_type`**: `"Dedicated"` (resource-specific tables) is the CAF-recommended default for new deployments. Use `"AzureDiagnostics"` only for backward compatibility with existing Log Analytics queries targeting the shared `AzureDiagnostics` table. Omitting the field leaves the choice to the provider (currently defaults to `"Dedicated"` where the resource supports it).

### AKS audit-log example (category_group)

For AKS clusters, Microsoft now exposes the full audit stream via the
`audit` category group rather than individual `kube-audit-admin` /
`kube-audit` categories. Capture both control-plane logs and metrics:

```hcl
diagnostic_settings = {
  aks = {
    name                           = "diag-aks-api-prod-gwc-001"
    target_resource_id             = dependency.aks.outputs.id
    log_analytics_workspace_id     = dependency.law.outputs.id
    log_analytics_destination_type = "Dedicated"
    log_groups                     = ["audit", "allLogs"]
    metrics                        = ["AllMetrics"]
  }
}
```

You can mix `logs` and `log_groups` in the same setting — both lists are
expanded into individual `enabled_log` blocks under the hood.

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of key => Diagnostic Setting ID |
| resources | Map of key => complete Diagnostic Setting object |
