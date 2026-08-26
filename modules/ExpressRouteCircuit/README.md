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
| [azurerm_express_route_circuit.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/express_route_circuit) | resource |
| [azurerm_express_route_circuit_peering.microsoft](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/express_route_circuit_peering) | resource |
| [azurerm_express_route_circuit_peering.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/express_route_circuit_peering) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bandwidth\_in\_mbps | Circuit bandwidth in Mbps. Must be one of the Azure-supported values: 50, 100, 200, 500, 1000, 2000, 5000, 10000.<br><br>Note: This module is scoped to the standard service-provider ER model. ExpressRouteDirect<br>(express\_route\_port\_id + bandwidth\_in\_gbps path) is OUT OF SCOPE — tracked as backlog enhancement. | `number` | n/a | yes |
| location | Azure region for the ExpressRoute circuit | `string` | n/a | yes |
| peering\_location | Peering location (e.g. Frankfurt, Amsterdam). Note: This module is scoped to the standard service-provider ER model. ExpressRouteDirect (express\_route\_port\_id + bandwidth\_in\_gbps path) is OUT OF SCOPE — tracked as backlog enhancement. | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| service\_provider\_name | ExpressRoute service provider (e.g. DE-CIX, Equinix). Note: This module is scoped to the standard service-provider ER model. ExpressRouteDirect (express\_route\_port\_id + bandwidth\_in\_gbps path) is OUT OF SCOPE — tracked as backlog enhancement. | `string` | n/a | yes |
| allow\_classic\_operations | Allow classic operations on the circuit | `bool` | `false` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| lock | Optional management lock (CanNotDelete or ReadOnly) | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| microsoft\_peering | Optional Microsoft Peering BGP config (for Office 365 / Azure PaaS reachability over ER).<br>Set to null to skip Microsoft Peering. Mirror shape of var.private\_peering plus<br>microsoft\_peering\_config sub-block with advertised\_public\_prefixes (the public IP<br>ranges your AS will advertise via the Microsoft Peering).<br><br>- `peer_asn` — On-premises BGP ASN.<br>- `primary_peer_address_prefix` — /30 subnet for the primary BGP session.<br>- `secondary_peer_address_prefix` — /30 subnet for the secondary BGP session.<br>- `vlan_id` — VLAN tag assigned by the provider (must differ from private\_peering.vlan\_id).<br>- `shared_key` — Optional MD5 BGP authentication key.<br>- `ipv4_enabled` — Enable IPv4 family (default true).<br>- `microsoft_peering_config.advertised_public_prefixes` — List of public IP prefixes to advertise.<br>- `microsoft_peering_config.advertised_communities` — Optional BGP community strings.<br>- `microsoft_peering_config.customer_asn` — Optional customer ASN for prefix ownership validation.<br>- `microsoft_peering_config.routing_registry_name` — Optional routing registry (e.g. ARIN, RIPE). | <pre>object({<br>    peer_asn                      = number<br>    primary_peer_address_prefix   = string<br>    secondary_peer_address_prefix = string<br>    vlan_id                       = number<br>    shared_key                    = optional(string)<br>    ipv4_enabled                  = optional(bool, true)<br>    microsoft_peering_config = object({<br>      advertised_public_prefixes = list(string)<br>      advertised_communities     = optional(list(string))<br>      customer_asn               = optional(number)<br>      routing_registry_name      = optional(string)<br>    })<br>  })</pre> | `null` | no |
| name | Optional. Explicit name. If null, computed from naming components. | `string` | `null` | no |
| private\_peering | Azure Private Peering configuration. Set to null to skip peering creation.<br><br>- `peer_asn` — On-premises BGP ASN.<br>- `primary_peer_address_prefix` — /30 subnet for the primary BGP session.<br>- `secondary_peer_address_prefix` — /30 subnet for the secondary BGP session.<br>- `vlan_id` — VLAN tag assigned by the provider.<br>- `shared_key` — Optional MD5 BGP authentication key.<br>- `ipv4_enabled` — Enable IPv4 family (default true).<br><br>NOTE: AzurePrivatePeering can only be created once the circuit has been<br>provisioned by the service provider (serviceProviderProvisioningState =<br>"Provisioned"). Apply this module twice if needed:<br>  1. With private\_peering = null  → creates circuit, captures serviceKey<br>  2. Share serviceKey with provider; wait for provisioning<br>  3. With private\_peering = {...} → adds the peering | <pre>object({<br>    peer_asn                      = number<br>    primary_peer_address_prefix   = string<br>    secondary_peer_address_prefix = string<br>    vlan_id                       = number<br>    shared_key                    = optional(string)<br>    ipv4_enabled                  = optional(bool, true)<br>  })</pre> | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| sku\_family | SKU family (MeteredData or UnlimitedData) | `string` | `"MeteredData"` | no |
| sku\_tier | SKU tier for the ExpressRoute circuit. Valid values: Basic, Standard, Premium, Local.<br><br>- Basic    — entry-level, limited route limits (preview in some regions)<br>- Standard — regional connectivity<br>- Premium  — global connectivity, higher route limits<br>- Local    — discounted local-only connectivity; REQUIRES sku\_family = "UnlimitedData"<br><br>Note: Local + MeteredData is rejected by the Azure API. | `string` | `"Standard"` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload suffix. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the ExpressRoute circuit |
| microsoft\_peering\_id | ID of the Microsoft Peering, or empty string when not configured. |
| name | The name of the ExpressRoute circuit |
| private\_peering\_azure\_ports | MSEE port allocations from Microsoft (primary/secondary). Empty strings until the provider finishes physical port plumbing — useful as a readiness signal. |
| private\_peering\_id | ID of the AzurePrivatePeering. Returns empty string when peering is not configured (phase 1) — Terragrunt strips null outputs from dependency objects, so empty string is used as the sentinel. |
| resource | The complete ExpressRoute circuit resource object (sensitive because it contains service\_key) |
| service\_key | Service Key (s-tag) — share with the provider to provision the circuit on their side |
| service\_provider\_provisioning\_state | Provider-side provisioning state (NotProvisioned / Provisioning / Provisioned) |
<!-- END_TF_DOCS -->
