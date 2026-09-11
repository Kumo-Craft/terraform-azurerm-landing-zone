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
