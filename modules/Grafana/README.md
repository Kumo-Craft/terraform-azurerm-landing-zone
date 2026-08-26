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
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/Grafana?ref=v0.2.46"

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
| grafana\_admin | ../RoleAssignment | n/a |
| grafana\_editor | ../RoleAssignment | n/a |
| grafana\_viewer | ../RoleAssignment | n/a |
| identity\_role\_assignments | ../RoleAssignment | n/a |
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_dashboard_grafana.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dashboard_grafana) | resource |
| [azurerm_dashboard_grafana_managed_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dashboard_grafana_managed_private_endpoint) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group where Grafana will be deployed. Must be created by the caller (e.g. via ../ResourceGroup at root). | `string` | n/a | yes |
| user\_assigned\_identity\_id | ARM ID of an existing User-Assigned Managed Identity to attach to Grafana. Compose with ../ManagedIdentity at root. | `string` | n/a | yes |
| user\_assigned\_identity\_principal\_id | Principal ID (object ID) of the UAMI. Used for role assignments. Required because Grafana SystemAssigned MI auto-assigns Monitoring Reader at AMW scope but UAMI does not. | `string` | n/a | yes |
| api\_key\_enabled | Enable Grafana API keys | `bool` | `false` | no |
| azure\_monitor\_workspace\_ids | List of Azure Monitor Workspace IDs to integrate | `list(string)` | `[]` | no |
| deterministic\_outbound\_ip\_enabled | Enable deterministic outbound IPs | `bool` | `true` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| grafana\_admin\_group\_object\_ids | Object IDs of Entra ID groups to assign as Grafana Admin | `list(string)` | `[]` | no |
| grafana\_editor\_group\_object\_ids | Object IDs of Entra ID groups to assign as Grafana Editor | `list(string)` | `[]` | no |
| grafana\_major\_version | Grafana major version | `string` | `"11"` | no |
| grafana\_sku | Grafana instance SKU (Standard or Essential) | `string` | `"Standard"` | no |
| grafana\_viewer\_group\_object\_ids | Object IDs of Entra ID groups to assign as Grafana Viewer | `list(string)` | `[]` | no |
| identity\_role\_assignments | A map of role assignments for the Grafana managed identity. The map key is<br>deliberately arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>Canonical shape B (scope-based, MI is the principal — see CONTRIBUTING.md<br>for the full convention).<br><br>- `role_definition_id_or_name`             - (Required) Role definition ID or name.<br>- `scope`                                  - (Required) Azure resource/MG scope.<br>- `condition`                              - (Optional) ABAC condition for the role assignment.<br>- `condition_version`                      - (Optional) Condition version. Valid values: "2.0".<br>- `description`                            - (Optional) Description of the role assignment.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check. Default false.<br>- `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    scope                                  = string<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| lock | Controls the Resource Lock configuration for this resource.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| managed\_private\_endpoints | Managed Private Endpoints from Grafana to private data sources (e.g. AMPLS).<br>Lets Grafana query Log Analytics / Azure Monitor over the private path so<br>workspaces protected by NSP / private-only do not reject Grafana egress.<br><br>Map key = short name used in the MPE resource name. Value:<br>- `private_link_resource_id`     - (Required) Target resource ID (e.g. AMPLS id).<br>- `group_ids`                    - (Optional) Subresource(s), e.g. ["azuremonitor"].<br>- `private_link_resource_region` - (Optional) Region of the target.<br>- `private_link_service_url`     - (Optional) FQDN for Private Link Service targets.<br>- `request_message`              - (Optional) Connection request message. | <pre>map(object({<br>    private_link_resource_id     = string<br>    group_ids                    = optional(list(string))<br>    private_link_resource_region = optional(string)<br>    private_link_service_url     = optional(string)<br>    request_message              = optional(string)<br>  }))</pre> | `{}` | no |
| name | Explicit Grafana name override (escape hatch). If null, derived from naming convention via ../Naming. | `string` | `null` | no |
| private\_endpoint | Optional Private Endpoint for the Grafana instance (subresource "grafana").<br><br>- `subnet_id`                     - (Required) Subnet ID for the PE NIC.<br>- `private_dns_zone_ids`          - (Optional) DNS zone IDs to attach (e.g. privatelink.grafana.azure.com).<br>- `private_ip_address`            - (Optional) Static private IP.<br>- `custom_network_interface_name` - (Optional) Custom NIC name. | <pre>object({<br>    subnet_id                     = string<br>    private_dns_zone_ids          = optional(list(string))<br>    private_ip_address            = optional(string)<br>    custom_network_interface_name = optional(string)<br>  })</pre> | `null` | no |
| public\_network\_access\_enabled | Enable public network access to Grafana. Set to false and use Private Endpoints in production. | `bool` | `false` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |
| workload | Workload name for naming convention (e.g. 'monitoring', 'platform'). | `string` | `"grafana"` | no |
| zone\_redundancy\_enabled | Enable zone redundancy for Azure Managed Grafana. If null (default), env-driven: true for environment=='prod', false otherwise. Explicit override always wins. NOTE: This setting is Azure-immutable post-create — cannot be changed without recreate. | `bool` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| endpoint | Grafana endpoint URL. |
| grafana\_endpoint | DEPRECATED — use output 'endpoint'. Will be removed in v0.3.0. |
| grafana\_id | DEPRECATED — use output 'id'. Will be removed in v0.3.0. |
| grafana\_name | DEPRECATED — use output 'name'. Will be removed in v0.3.0. |
| grafana\_resource | DEPRECATED — use output 'resource'. Will be removed in v0.3.0. |
| id | Grafana resource ID. |
| name | Grafana resource name. |
| private\_endpoint\_id | Grafana Private Endpoint ID (null when private\_endpoint is not configured) |
| resource | Full azurerm\_dashboard\_grafana resource object. |
<!-- END_TF_DOCS -->
