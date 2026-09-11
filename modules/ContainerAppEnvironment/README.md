# ContainerAppEnvironment

Deploys an Azure **Container Apps Environment** (`Microsoft.App/managedEnvironments`) — the shared, secure boundary that hosts Container Apps (shared VNet, logging, Dapr, and ingress). This is the **prerequisite** for the Container App module.

## Highlights

- **Logging**: `log-analytics` (default, requires a Log Analytics Workspace), `azure-monitor` (diagnostic settings), or streamed-only (`logs_destination = null`).
- **VNet integration**: `infrastructure_subnet_id` (subnet delegated to `Microsoft.App/environments`) — enables internal-only ingress (`internal_load_balancer_enabled`) and `zone_redundancy_enabled`.
- **Workload profiles**: dedicated compute (D/E/NC series) or Consumption. Omit for a Consumption-only environment.
- Optional managed identity, Dapr Application Insights, mTLS, public network access toggle, lock + tags.

> **Subnet sizing**: min **/23** for Consumption-only, **/27** for Workload-profile environments.

## Usage

### Simple (public, Consumption, Log Analytics)

```hcl
module "aca_env" {
  source = "../ContainerAppEnvironment"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "web"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-aca"

  logs_destination           = "log-analytics"
  log_analytics_workspace_id = module.law.id

  tags = { Environment = "Production" }
}
```

### Private (internal, zone-redundant, VNet-injected, workload profiles)

```hcl
module "aca_env" {
  source = "../ContainerAppEnvironment"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "web"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-aca"

  log_analytics_workspace_id = module.law.id

  infrastructure_subnet_id       = "/subscriptions/.../subnets/snet-aca" # delegated to Microsoft.App/environments
  internal_load_balancer_enabled = true
  zone_redundancy_enabled        = true
  public_network_access          = "Disabled"

  workload_profiles = [
    { name = "Consumption", workload_profile_type = "Consumption" },
    { name = "dedicated-d4", workload_profile_type = "D4", minimum_count = 1, maximum_count = 3 },
  ]
}
```

### Subnet delegation (prerequisite for VNet integration)

```hcl
resource "azurerm_subnet" "aca" {
  # ... min /23 (Consumption) or /27 (Workload profiles)
  delegation {
    name = "aca"
    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
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
| name | Explicit name (2-32 chars). If null, `cae-{acr}-{env}-{region}-{workload}`. | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components (required unless `name`) | `string` | `null` | No |
| location / resource_group_name | — | `string` | -- | Yes |
| logs_destination | `log-analytics` / `azure-monitor` / null (streamed) | `string` | `"log-analytics"` | No |
| log_analytics_workspace_id | LAW ID (required for log-analytics; null for azure-monitor) | `string` | `null` | No |
| infrastructure_subnet_id | Subnet for VNet integration (delegated to Microsoft.App/environments) | `string` | `null` | No |
| internal_load_balancer_enabled | Internal-only ingress (requires subnet) | `bool` | `false` | No |
| zone_redundancy_enabled | Spread across zones (requires subnet) | `bool` | `false` | No |
| infrastructure_resource_group_name | Platform-managed infra RG name (workload profiles only) | `string` | `null` | No |
| public_network_access | `Enabled` / `Disabled` (null = Azure default) | `string` | `null` | No |
| workload_profiles | Dedicated/Consumption profiles (empty = Consumption-only) | `list(object)` | `[]` | No |
| identity | Managed identity block | `object` | `null` | No |
| dapr_application_insights_connection_string | Dapr telemetry (sensitive) | `string` | `null` | No |
| mutual_tls_enabled | mTLS between apps (preview) | `bool` | `false` | No |
| lock | Management lock | `object` | `null` | No |
| tags | Tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Environment resource ID — pass to the Container App module |
| name | Environment name |
| default_domain | Default resolvable domain (`<app>.<default_domain>`) |
| static_ip_address | Static IP (public, or internal-subnet IP when internal LB on) |
| custom_domain_verification_id | For binding custom domains to apps |
| identity_principal_id | System-assigned identity principal ID (null if none) |
| resource | Complete resource object (sensitive) |

## Notes

- **Workload profiles are immutable in spirit.** An environment created **without** profiles can never have them added later (and vice-versa) — switching forces a full recreate. Decide Consumption-only vs Workload-profile up front.
- **Internal LB / zone redundancy require a subnet** (enforced by variable validation) and are `ForceNew`.
- **Private environment** = `internal_load_balancer_enabled = true` + a private DNS zone for `default_domain` pointing at `static_ip_address` (+ `public_network_access = "Disabled"`).

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
| [azurerm_container_app_environment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region where the Container App Environment will be deployed | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| dapr\_application\_insights\_connection\_string | Optional Application Insights connection string for Dapr service-to-service telemetry. | `string` | `null` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| identity | Optional managed identity for the environment (e.g. to pull images from ACR or read<br>Key Vault-backed certificates at the environment scope).<br><br>- `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.<br>- `identity_ids` - (Optional) UAMI IDs. Required when type includes 'UserAssigned'. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), [])<br>  })</pre> | `null` | no |
| infrastructure\_resource\_group\_name | Optional. Name of the platform-managed infrastructure resource group. Only valid when a workload\_profile is specified. | `string` | `null` | no |
| infrastructure\_subnet\_id | Optional. Existing subnet for the Container Apps control plane (VNet integration).<br>Minimum /23 for Consumption-only, /27 for Workload-profile environments. The subnet<br>must be delegated to Microsoft.App/environments. Required for internal LB / zone redundancy. | `string` | `null` | no |
| internal\_load\_balancer\_enabled | Run the environment in internal-only mode (no public ingress). Requires infrastructure\_subnet\_id. | `bool` | `false` | no |
| lock | Optional management lock (CanNotDelete or ReadOnly). | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| log\_analytics\_workspace\_id | Log Analytics Workspace ID to link. Required when logs\_destination = 'log-analytics'; must be null when logs\_destination = 'azure-monitor'. | `string` | `null` | no |
| logs\_destination | Where application logs go: 'log-analytics' (requires log\_analytics\_workspace\_id), 'azure-monitor' (diagnostic settings), or null (streamed only). | `string` | `"log-analytics"` | no |
| mutual\_tls\_enabled | Enable mutual TLS (mTLS) between apps. Public preview — may add latency. | `bool` | `false` | no |
| name | Optional. Explicit Container App Environment name (2-32 chars, start with a letter, lowercase letters/digits/hyphens). If null, computed as cae-{acr}-{env}-{region}-{workload}. | `string` | `null` | no |
| public\_network\_access | Public network access for the environment. 'Enabled' or 'Disabled' (null = Azure default). Set 'Disabled' with internal LB + private endpoints for a private environment. | `string` | `null` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, api) | `string` | `null` | no |
| tags | Tags to apply to the Container App Environment | `map(string)` | `{}` | no |
| workload | Workload name for naming convention. Keep short — composed name must be <= 32 chars. | `string` | `null` | no |
| workload\_profiles | Workload profiles for the environment. Empty = a Consumption-only environment.<br><br>- `name`                  - (Required) Profile name. A `Consumption` profile must be named "Consumption".<br>- `workload_profile_type` - (Required) e.g. "Consumption", "D4", "D8", "E4", "NC24-A100"…<br>- `minimum_count` / `maximum_count` - (Optional) Instance bounds for dedicated profiles.<br><br>Note: an environment created without profiles can NEVER add them later (and vice-versa) —<br>switching forces a full recreate. | <pre>list(object({<br>    name                  = string<br>    workload_profile_type = string<br>    minimum_count         = optional(number)<br>    maximum_count         = optional(number)<br>  }))</pre> | `[]` | no |
| zone\_redundancy\_enabled | Spread the environment across availability zones. Requires infrastructure\_subnet\_id. Recommended true for production. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| custom\_domain\_verification\_id | The custom domain verification ID for binding custom domains to apps in this environment. |
| default\_domain | The default, publicly resolvable domain of the environment (apps get <app>.<default\_domain>). |
| id | The Container App Environment resource ID. Pass to the Container App module's container\_app\_environment\_id. |
| identity\_principal\_id | The system-assigned identity principal ID (null when no system-assigned identity). |
| name | The Container App Environment name |
| resource | The complete Container App Environment resource object. |
| static\_ip\_address | The static IP of the environment (public, or internal-subnet IP when internal\_load\_balancer\_enabled = true). Use for DNS / private DNS zone records. |
<!-- END_TF_DOCS -->
