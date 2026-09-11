# ExpressRouteCircuit

Manages an Azure ExpressRoute Circuit with optional Azure Private Peering and optional Microsoft
Peering. Designed to compose upstream of `../vwan` for hub-and-spoke ER deployments.

## Scope

This module is scoped to the **standard service-provider ER model** (provider + peering location +
`bandwidth_in_mbps`).

**ExpressRouteDirect is OUT OF SCOPE** (would require `express_route_port_id` + `bandwidth_in_gbps`
path with XOR validator). Tracked as future enhancement.

## Usage

### Standalone (Terragrunt)

```hcl
terraform {
  source = "${get_repo_root()}/modules/ExpressRouteCircuit"
}

inputs = {
  subscription_acronym  = "con"
  environment           = "prod"
  region_code           = "gwc"
  workload              = "backbone"
  location              = "germanywestcentral"
  resource_group_name   = "rg-network-prod-gwc"
  service_provider_name = "Equinix"
  peering_location      = "Frankfurt"
  bandwidth_in_mbps     = 1000
  sku_tier              = "Standard"
  sku_family            = "MeteredData"

  # Phase 2 — add after provider confirms Provisioned state
  private_peering = {
    peer_asn                      = 65001
    primary_peer_address_prefix   = "10.0.1.0/30"
    secondary_peer_address_prefix = "10.0.1.4/30"
    vlan_id                       = 100
  }
}
```

### Composition with vwan

```hcl
# Phase 1: Create circuit, capture service_key for provider
module "circuit" {
  source = "../ExpressRouteCircuit"

  subscription_acronym  = "con"
  environment           = "prod"
  region_code           = "gwc"
  workload              = "backbone"
  location              = "germanywestcentral"
  resource_group_name   = "rg-network-prod-gwc"
  service_provider_name = "Equinix"
  peering_location      = "Frankfurt"
  bandwidth_in_mbps     = 1000
  sku_tier              = "Standard"
  sku_family            = "MeteredData"

  private_peering = {
    peer_asn                      = 65001
    primary_peer_address_prefix   = "10.0.1.0/30"
    secondary_peer_address_prefix = "10.0.1.4/30"
    vlan_id                       = 100
  }
}

# Phase 2: Reference the circuit's private peering in vwan
module "vwan" {
  source = "../vwan"

  # ... vwan variables ...

  express_route_connections = {
    "er-conn-backbone" = {
      virtual_hub_key                  = "hub-gwc"
      express_route_circuit_peering_id = module.circuit.private_peering_id
    }
  }
}
```

## Two-phase apply workflow

ExpressRoute provisioning requires coordination with the service provider:

1. **Phase 1 — create circuit** (`private_peering = null`): Terraform creates the circuit resource
   and exposes `output.service_key`. Share the service key with your provider (Equinix, DE-CIX,
   etc.) and wait for `service_provider_provisioning_state` to become `"Provisioned"`.

2. **Phase 2 — wait for provider**: The provider provisions their side. Poll
   `output.service_provider_provisioning_state` until it returns `"Provisioned"`.

3. **Phase 3 — add peering** (set `private_peering = {...}`): Apply again to create the BGP peering
   session. Azure Private Peering fails with an API error if the circuit is not yet in Provisioned
   state.

The module's `var.private_peering = null` default and the `count` guard on
`azurerm_express_route_circuit_peering.private` support this two-phase pattern natively.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | `null` | No | Explicit circuit name. If null, computed as `erc-{acr}-{env}-{region}-{workload}`. |
| `subscription_acronym` | `string` | `null` | Required when `name` is null | Subscription acronym (2-5 lowercase letters, e.g. `con`). |
| `environment` | `string` | `null` | Required when `name` is null | Environment (2-4 lowercase letters, e.g. `prod`). |
| `region_code` | `string` | `null` | Required when `name` is null | Region code (2-5 lowercase letters, e.g. `gwc`). |
| `workload` | `string` | `null` | Required when `name` is null | Workload suffix. |
| `location` | `string` | — | Yes | Azure region for the circuit. |
| `resource_group_name` | `string` | — | Yes | Resource group name. |
| `service_provider_name` | `string` | — | Yes | ExpressRoute service provider (e.g. `Equinix`, `DE-CIX`). Standard ER model only. |
| `peering_location` | `string` | — | Yes | Peering location (e.g. `Frankfurt`, `Amsterdam`). Standard ER model only. |
| `bandwidth_in_mbps` | `number` | — | Yes | Circuit bandwidth. Must be: 50, 100, 200, 500, 1000, 2000, 5000, or 10000. |
| `sku_tier` | `string` | `"Standard"` | No | SKU tier: `Basic`, `Standard`, `Premium`, or `Local`. `Local` requires `sku_family = "UnlimitedData"`. |
| `sku_family` | `string` | `"MeteredData"` | No | SKU family: `MeteredData` or `UnlimitedData`. |
| `allow_classic_operations` | `bool` | `false` | No | Allow classic operations on the circuit. |
| `private_peering` | `object` | `null` | No | Azure Private Peering BGP config. See variable description for fields. Sensitive. |
| `microsoft_peering` | `object` | `null` | No | Microsoft Peering BGP config (Office 365 / Azure PaaS). See variable description for fields. Sensitive. |
| `lock` | `object` | `null` | No | Management lock (`CanNotDelete` or `ReadOnly`). |
| `tags` | `map(string)` | `{}` | No | Tags to apply to all resources. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | The ID of the ExpressRoute circuit. |
| `name` | The name of the ExpressRoute circuit. |
| `service_key` | Service Key — share with the provider to provision the circuit. **Sensitive.** |
| `service_provider_provisioning_state` | Provider-side state: `NotProvisioned` / `Provisioning` / `Provisioned`. |
| `private_peering_id` | ID of the AzurePrivatePeering, or empty string when not configured. **Sensitive.** |
| `microsoft_peering_id` | ID of the MicrosoftPeering, or empty string when not configured. **Sensitive.** |
| `private_peering_azure_ports` | MSEE primary/secondary port allocations (readiness signal). **Sensitive.** |
| `resource` | The full circuit resource object. **Sensitive.** |

## Breaking changes (v0.2.23)

### Naming slug aligned with upstream Azure/naming/azurerm

v0.2.22 and earlier produced circuit names with prefix `er-` (manual slug). v0.2.23 uses the
upstream-canonical `erc-` slug via `module.naming.result.express_route_circuit.name` — aligned with
all sibling modules (KeyVault `kv-`, StorageAccount `st-`, vwan `vwan-`).

**Impact**: Callers who DID NOT pass `var.name` and relied on the convention name see an Azure-side
resource rename (`er-con-prod-gwc-backbone` → `erc-con-prod-gwc-backbone`). **For ExpressRoute
circuits, rename triggers destroy+recreate which is CATASTROPHIC** (lost provisioning state, new
service_key required from carrier, multi-week re-provisioning).

**Migration recipe — DO NOT just apply the upgrade**:

1. **Before upgrading**: pin to v0.2.22 first.
2. **Capture the current name explicitly**:
   ```hcl
   module "circuit" {
     source = "..."
     name   = "er-con-prod-gwc-backbone"   # pin the legacy name explicitly
     ...
   }
   ```
3. **Then upgrade to v0.2.23**: with `var.name` set, the override branch wins via the XOR escape
   hatch. No rename, no destroy.
4. **For NEW deployments**: omit `var.name` to use the new canonical `erc-` slug.

Callers passing `var.name` explicitly today are byte-for-byte compatible — no action needed.

### private_peering and microsoft_peering outputs now sensitive

`private_peering_id`, `microsoft_peering_id`, and `private_peering_azure_ports` are now marked
`sensitive = true` (consequence of F-10: whole-object sensitive on peering variables). Downstream
`dependency` blocks in Terragrunt that reference these outputs may require explicit
`sensitive = true` handling.
