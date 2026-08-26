# Grafana

Deploys an Azure Managed Grafana instance. The caller provides the resource group and user-assigned managed identity — compose with `../ResourceGroup` and `../ManagedIdentity` at root. Includes Azure Monitor Workspace integrations and Entra ID RBAC group assignments (Admin, Editor, Viewer).

## Breaking changes (v0.2.46)

### F-2 — Inline ResourceGroup and UserAssignedIdentity removed

The module no longer creates the RG or UAMI internally. You must create them at the caller root and pass them in via the three new required inputs.

**Migration recipe**

1. Move RG creation to caller root using `../ResourceGroup`.
2. Move UAMI creation to caller root using `../ManagedIdentity`.
3. Run state moves before the next apply:
   ```
   terraform state mv module.grafana.azurerm_resource_group.this \
     module.resource_group.azurerm_resource_group.this["grafana"]

   terraform state mv module.grafana.azurerm_user_assigned_identity.this \
     module.managed_identity.azurerm_user_assigned_identity.this
   ```
4. Add the three new required inputs to your module call:
   ```hcl
   resource_group_name                 = module.resource_group.names["grafana"]
   user_assigned_identity_id           = module.managed_identity.id
   user_assigned_identity_principal_id = module.managed_identity.principal_id
   ```
5. Remove the old outputs `resource_group_name`, `identity_id`, `identity_principal_id`, `identity_client_id` from any downstream references (no longer emitted by this module).

> **Note (cleanup):** the `removed { lifecycle.destroy = false }` tombstones and the `moved` role-assignment blocks that used to live in `main.tf` (state-migration aids for the v0.2.46 refactor) have been dropped now that no caller retains pre-v0.2.46 state. Any consumer upgrading across the v0.2.46 boundary from very old state must land on an intermediate version that still carries them before jumping to a version without.

Canonical RG-drop precedents: NetworkStack v0.2.8, PaloCluster v0.2.25, PrivateDnsZones v0.2.9.

### F-3 — Output renames

| Old name | New canonical name | Deprecated alias kept until v0.3.0 |
|---|---|---|
| `grafana_id` | `id` | `grafana_id` |
| `grafana_name` | `name` | `grafana_name` |
| `grafana_resource` | `resource` | `grafana_resource` |
| `grafana_endpoint` | `endpoint` | `grafana_endpoint` |

## Usage

### Standalone

```hcl
module "grafana" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/Grafana?ref=v0.2.46"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"

  resource_group_name                 = module.resource_group.names["grafana"]
  user_assigned_identity_id           = module.managed_identity.id
  user_assigned_identity_principal_id = module.managed_identity.principal_id

  grafana_sku           = "Standard"
  grafana_major_version = "11"

  azure_monitor_workspace_ids = [
    "/subscriptions/.../providers/Microsoft.Monitor/accounts/amw-mgm-prod-gwc-01"
  ]

  identity_role_assignments = {
    monitoring_reader = {
      scope                      = "/providers/Microsoft.Management/managementGroups/mg-lzr-prod"
      role_definition_id_or_name = "Monitoring Reader"
    }
  }

  grafana_admin_group_object_ids  = ["aaaaaaaa-0000-0000-0000-000000000001"]
  grafana_viewer_group_object_ids = ["aaaaaaaa-0000-0000-0000-000000000002"]

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/Grafana"
}

inputs = {
  subscription_acronym        = include.sub.locals.subscription_acronym
  environment                 = include.root.inputs.environment
  region_code                 = include.root.inputs.region_code
  location                    = include.root.inputs.location

  resource_group_name                 = dependency.rg.outputs.names["grafana"]
  user_assigned_identity_id           = dependency.mi.outputs.id
  user_assigned_identity_principal_id = dependency.mi.outputs.principal_id

  azure_monitor_workspace_ids = [dependency.amw.outputs.id]

  identity_role_assignments = {
    monitoring_reader = {
      scope                      = "/providers/Microsoft.Management/managementGroups/mg-lzr-${include.root.inputs.environment}"
      role_definition_id_or_name = "Monitoring Reader"
    }
    monitoring_data_reader = {
      scope                      = "/providers/Microsoft.Management/managementGroups/mg-lzr-${include.root.inputs.environment}"
      role_definition_id_or_name = "Monitoring Data Reader"
    }
  }

  grafana_admin_group_object_ids = ["aaaaaaaa-0000-0000-0000-000000000001"]
  tags                           = include.root.inputs.common_tags
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
| name | Explicit Grafana name override (escape hatch). If null, derived from naming convention. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm) | `string` | `null` | No* |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No* |
| region_code | Region code (e.g. gwc) | `string` | `null` | No* |
| workload | Workload name for naming convention | `string` | `"grafana"` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Caller-provided RG name (see Breaking changes v0.2.46) | `string` | -- | Yes |
| user_assigned_identity_id | ARM ID of UAMI to attach to Grafana | `string` | -- | Yes |
| user_assigned_identity_principal_id | Principal ID of UAMI (for role assignments) | `string` | -- | Yes |
| grafana_sku | Standard or Essential | `string` | `"Standard"` | No |
| grafana_major_version | Grafana major version | `string` | `"11"` | No |
| public_network_access_enabled | Enable public access | `bool` | `false` | No |
| zone_redundancy_enabled | Enable zone redundancy. null = env-driven (true if environment=='prod', else false). Immutable post-create. | `bool` | `null` | No |
| api_key_enabled | Enable API keys | `bool` | `false` | No |
| deterministic_outbound_ip_enabled | Enable deterministic outbound IPs | `bool` | `true` | No |
| azure_monitor_workspace_ids | AMW IDs to integrate | `list(string)` | `[]` | No |
| identity_role_assignments | Map of role assignments for the Grafana UAMI. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| grafana_admin_group_object_ids | Entra ID group object IDs for Grafana Admin | `list(string)` | `[]` | No |
| grafana_editor_group_object_ids | Entra ID group object IDs for Grafana Editor | `list(string)` | `[]` | No |
| grafana_viewer_group_object_ids | Entra ID group object IDs for Grafana Viewer | `list(string)` | `[]` | No |
| tags | Tags | `map(string)` | `{}` | No |

\* When `name` is null, all 4 naming components (`subscription_acronym`, `environment`, `region_code`, `workload`) must be provided.

## Outputs

| Name | Description |
|------|-------------|
| id | Grafana resource ID (canonical) |
| name | Grafana resource name (canonical) |
| resource | Full azurerm_dashboard_grafana resource object (canonical) |
| endpoint | Grafana endpoint URL |
| private_endpoint_id | Private Endpoint ID (null if not configured) |
| grafana_id | DEPRECATED — use `id`. Removed in v0.3.0. |
| grafana_name | DEPRECATED — use `name`. Removed in v0.3.0. |
| grafana_resource | DEPRECATED — use `resource`. Removed in v0.3.0. |
| grafana_endpoint | DEPRECATED — use `endpoint`. Removed in v0.3.0. |

## Zone Redundancy is immutable

`zone_redundancy_enabled` cannot be changed after the Grafana instance is
created — Azure rejects the update. Flipping the value requires a full
**destroy + recreate**, which loses:

- Custom dashboards (export them via the Grafana API beforehand)
- Datasource links to LAW / AMW (must be re-linked)
- Entra ID RBAC group assignments (recreated by this module, but plan/apply
  ordering matters)
- Plugins, contact points, alert rules

When `zone_redundancy_enabled` is null (default), the module applies env-driven logic:
`true` if `environment == "prod"`, `false` otherwise.

**Decision matrix for this Landing Zone**:

| Environment | ZR | Rationale |
|---|---|---|
| **nprd** | `false` (env-driven) | Cost-saving on a consultation-only tool; break-glass via Azure Monitor portal during a zone incident is acceptable. Tracked as F-FIN-4 (closed by-design) in `audit-live-nprd.md` and exempted from the `Audit-ZoneResiliency` policy via `landing-zone/platform/management/policy-exemptions/grafana-zr-waiver`. |
| **prod** | `true` (env-driven) | Grafana is *most needed* during a zone incident (to visualize the affected resources). Env-driven default sets `zone_redundancy_enabled = true` automatically — no explicit caller input required. |

To override: set `zone_redundancy_enabled = false` (or `true`) explicitly. The explicit value always wins over the env-driven default.
