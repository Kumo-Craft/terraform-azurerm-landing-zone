# NetworkStack

Generic regional spoke (or hub) network bundle: RG + Network Watcher + vnet +
Route Table + NSGs + Subnets, in a single Terraform/Terragrunt apply.

Replaces the 5-6 separate deployments pattern (`network-watcher`, `network-{wl}`,
`nsg-{wl}`, `rt-{wl}`, `subnet-{wl}`) with one composed module. Designed to
host any workload — AVD, AKS, App Service, Bastion, NetApp, generic VMs,
dedicated PE subnets, or any combination thereof.

## What it builds

- (optional) `rg-{prefix}-network`
- (optional) `nw-{prefix}-network` (Network Watcher)
- `vnet-{prefix}-{workload}` with custom DNS, DDoS Standard, encryption (opt-in)
- `rt-{prefix}-{workload}` with default route → NVA, BGP propagation off
- `nsg-{prefix}-{subnet_key}` per subnet (create_nsg=true)
- subnets via `azapi_resource` (1-shot PUT with NSG + RT — satisfies
  `Deny-Subnet-Without-Nsg` policy)

## Prerequisites

- Terraform ≥ 1.12
- Provider `hashicorp/azurerm ~> 4.0`
- Provider `Azure/azapi ~> 2.0`
- Provider `hashicorp/time >= 0.9.0`

## Usage examples

### AVD spoke (4 subnets — session hosts + PEs)

```hcl
module "network_avd" {
  source = "../../modules/NetworkStack"

  subscription_acronym = "avd"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "spoke"

  location           = "germanywestcentral"
  vnet_address_space = ["10.239.5.0/24"]

  dns_servers               = ["10.239.200.36"]   # Palo ILB / DNS proxy
  ddos_protection_plan_id   = "/subscriptions/.../ddosProtectionPlans/ddos-shared"
  default_route_next_hop_ip = "10.239.200.36"     # default 0.0.0.0/0 → Palo ILB

  subnets = {
    hosts = {
      cidr = "10.239.5.0/26"
    }
    "pe-avd" = {
      cidr                              = "10.239.5.64/28"
      private_endpoint_network_policies = "Disabled"
    }
    "pe-storage" = {
      cidr                              = "10.239.5.80/28"
      private_endpoint_network_policies = "Disabled"
    }
    "pe-kv" = {
      cidr                              = "10.239.5.96/28"
      private_endpoint_network_policies = "Disabled"
    }
  }

  tags = { Workload = "avd" }
}
```

### AKS spoke (with API server delegation)

```hcl
module "network_aks" {
  source = "../../modules/NetworkStack"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "spoke"

  location                  = "germanywestcentral"
  vnet_address_space        = ["10.238.0.0/24"]
  dns_servers               = ["10.238.200.36"]
  ddos_protection_plan_id   = local.ddos_id
  default_route_next_hop_ip = "10.238.200.36"

  subnets = {
    nodes = {
      cidr = "10.238.0.128/26"
    }
    pods = {
      cidr = "10.238.0.64/28"
    }
    apiserver = {
      cidr = "10.238.0.32/28"
      delegation = {
        name         = "aks-apiserver"
        service_name = "Microsoft.ContainerService/managedClusters"
      }
    }
    storages = {
      cidr                              = "10.238.0.48/28"
      private_endpoint_network_policies = "Disabled"
    }
  }
}
```

### Hub vnet with shared services + Bastion

```hcl
module "network_hub" {
  source = "../../modules/NetworkStack"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "shared"

  location           = "germanywestcentral"
  vnet_address_space = ["10.238.204.0/23"]

  # Hub doesn't route through itself
  create_route_table = false

  subnets = {
    bastion = {
      name = "AzureBastionSubnet"
      cidr = "10.238.204.0/26"
      # create_nsg defaults to true
    }
    "dns-in" = {
      cidr               = "10.238.204.64/28"
      attach_route_table = false
      delegation = {
        name         = "Microsoft.Network.dnsResolvers"
        service_name = "Microsoft.Network/dnsResolvers"
      }
    }
    "dns-out" = {
      cidr               = "10.238.204.80/28"
      attach_route_table = false
      delegation = {
        name         = "Microsoft.Network.dnsResolvers"
        service_name = "Microsoft.Network/dnsResolvers"
      }
    }
  }
}
```

### Special-case subnets

| Subnet name | Settings |
|---|---|
| `AzureBastionSubnet` | `create_nsg = true` with Bastion rules; `attach_route_table = false` (routes per design) |
| `GatewaySubnet` | `create_nsg = false` (Azure forbids); `attach_route_table = false` |
| `AzureFirewallSubnet` | `create_nsg = false` (Azure forbids); `attach_route_table = false` |
| `AzureFirewallManagementSubnet` | `create_nsg = false`; `attach_route_table = false` |

### Per-subnet dedicated route table (`routes`)

For a subnet that must route **specific** prefixes but where the default `0.0.0.0/0` route is forbidden — e.g. an **Entra Domain Services** subnet, where Microsoft blocks touching the default route but allows targeted UDRs — declare `routes` on the subnet. The module creates a **dedicated** route table `rt-{prefix}-{subnet_key}` holding **only** those routes (no default route) and attaches it. This is **mutually exclusive** with the shared route table, so set `attach_route_table = false`.

```hcl
subnets = {
  adds = {
    cidr               = "10.238.212.0/27"
    attach_route_table = false          # required — exclusive with `routes`
    routes = {
      to-shared-resolver = {
        address_prefix         = "10.238.204.0/23"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.238.200.36"
      }
    }
  }
}
```

## Outputs

| Output | Description |
|---|---|
| `vnet_id`, `vnet_name`, `vnet_address_space` | vnet identifiers |
| `subnet_ids`, `subnet_names` | maps keyed by the subnet identifier you used in the input |
| `nsg_ids`, `nsg_names` | NSG maps (only for subnets with create_nsg=true) |
| `route_table_id`, `route_table_name` | RT identifiers (null if not created) |
| `network_watcher_id`, `network_watcher_name` | NW identifiers (null if not created) |
| `resource_group_name` | RG name passthrough (caller-provided) |
| `hub_peering_id` | Resource ID of the spoke->hub peering, or null when `hub_peering` not set. |

## Best practices baked in

- **NSG required by default** on every subnet (ALZ `Deny-Subnet-Without-Nsg`)
- **NSG attached at create time** (azapi 1-shot PUT)
- **BGP propagation OFF** on the route table (UDRs win deterministically)
- **`defaultOutboundAccess = false`** on all subnets (future-proof for Microsoft's
  Sept 2025 retirement of default outbound access)
- **DDoS Standard** referenceable via `ddos_protection_plan_id` (recommended for
  prod-facing spokes)
- **Custom DNS** wired to the NVA / DNS resolver IP for hub-and-spoke models
- **`encryption.enforcement`** opt-in for east-west encrypted-only enforcement
- **flow_timeout_in_minutes** opt-in for long-running connections (default 4 min
  Azure timeout can break long-poll patterns)

## Composed submodules

- `../NSG` — one NSG per subnet that has `create_nsg = true`
- `../VNetPeering` — spoke->hub peering when `hub_peering` is set (composed in v0.2.6; state-migrated automatically via `moved` block — no manual state surgery required)
- `../RouteTable` — the shared route table + routes when `create_route_table = true` (composed in v0.2.7; state-migrated automatically via `moved` blocks — no manual state surgery required), **and** one dedicated route table per subnet that declares `routes` (named `rt-{prefix}-{subnet_key}`, no default 0.0.0.0/0)
- `../NetworkWatcher` — network watcher when `create_network_watcher = true` (composed in v0.2.8; state-migrated automatically via `moved` block — no manual state surgery required)

## Migration notes

NetworkStack underwent two composition refactors that are transparent to callers:

### v0.2.5 — NSG composition

The inline `azurerm_network_security_group.this` resource was replaced by `module "nsg" { source = "../NSG" }`. State migration is handled automatically by a bare-collection `moved` block in `main.tf` — running `terraform plan` after upgrading shows no changes for existing callers. The public interface (`var.subnets` with `create_nsg`/`nsg_rules`, outputs `nsg_ids`/`nsg_names`) is byte-for-byte preserved.

### v0.2.6 — VNetPeering composition

The inline `azurerm_virtual_network_peering.hub` resource (count-based) was replaced by `module "hub_peering" { source = "../VNetPeering" }` with a fixed map key `"hub"`. The Azure-side peering name is preserved via the new `name` override field on the VNetPeering map entry. State migration via an indexed `moved` block — no manual `terraform state mv` required. The public interface (`var.hub_peering`, output `hub_peering_id`) is byte-for-byte preserved.

Callers cannot opt out of either migration — the `moved` blocks are authoritative. If you need to keep the old inline resources unmanaged (highly unusual), do not upgrade past v0.2.4.

### v0.2.7 — RouteTable composition

The inline `azurerm_route_table.this[0]` + `azurerm_route.default[0]` + `azurerm_route.extra` resources were replaced by `module "route_table" { source = "../RouteTable" }`. State migration is handled by three `moved` blocks in `main.tf`:

- Route table: `azurerm_route_table.this[0]` → `module.route_table[0].azurerm_route_table.this`
- Default route (if configured): `azurerm_route.default[0]` → `module.route_table[0].azurerm_route.this["default-udr"]`
- Extra routes: `azurerm_route.extra` (bare collection) → `module.route_table[0].azurerm_route.this`

**Impact for callers:** running `terraform plan` after upgrading shows zero Azure-side changes — the existing separate route resources move cleanly into the new module's state under the same Azure-side identities. The Azure-side resource names are preserved byte-for-byte via `name = local.rt_name` (still `rt-{prefix}-{workload}`, NOT the RouteTable module's default upstream `route-*` slug). The public interface (`var.create_route_table`, `var.default_route_*`, `var.extra_routes`, outputs `route_table_id` / `route_table_name`) is unchanged.

Note: RouteTable v0.2.7 itself underwent an inline-route → separate-resource refactor that IS breaking for callers consuming RouteTable directly (not via NetworkStack). NetworkStack callers are unaffected because their state already used separate route resources. See [RouteTable v0.2.7 breaking changes](../RouteTable/README.md#breaking-changes-v027) for the standalone-caller migration.

### v0.2.8 — Resource Group removal (BREAKING)

NetworkStack no longer creates or looks up a resource group. `var.resource_group_name` is now required (`nullable = false`).

**Removed variables:**

- `var.create_resource_group` — deleted. Callers must always provide an existing RG.
- `var.resource_group_workload` — deleted. Use `var.workload` (standard naming segment).

**Removed output:**

- `output.resource_group_id` — deleted. Use a `data "azurerm_resource_group" "this"` in your root module if you need the ID.

**Impact for callers who had `create_resource_group = true`:**

The inline `azurerm_resource_group.this` resource is gone. To keep the RG without destroying it during the upgrade, callers must:

1. Move the RG resource to their root config (e.g. via `../ResourceGroup` module).
2. Add to their root config:

   ```hcl
   removed {
     from = module.network_stack.azurerm_resource_group.this
     lifecycle {
       destroy = false
     }
   }
   ```

3. Pass the same RG name as `var.resource_group_name` to NetworkStack.
4. Use `terraform state mv` to move the RG state into the new owner (the `../ResourceGroup` module call or whatever creates the RG in the root).

**Impact for callers who had `create_resource_group = false`:**

Trivial — they already passed `var.resource_group_name`. Just delete the now-removed `var.create_resource_group = false` line from their config. No state surgery.

**Naming change for Network Watcher:**

The `nw_name_default` template changed from `nw-{prefix}-{resource_group_workload}` to `nw-{prefix}-{workload}`. If your previous deployment had `resource_group_workload != workload`, your NW resource name changes — destroy+create. To preserve byte-for-byte, pass the old name explicitly via `var.network_watcher_name` (existing override).

**NetworkWatcher composition (v0.2.8):**

The inline `azurerm_network_watcher.this[0]` is now composed via `module "network_watcher" { source = "../NetworkWatcher" }`. State migration is automatic via a `moved` block in `main.tf`:

- `azurerm_network_watcher.this[0]` → `module.network_watcher[0].azurerm_network_watcher.this`

Existing callers with `create_network_watcher = true` AND `resource_group_workload == workload`: zero Azure-side impact, name preserved byte-for-byte. Callers with `resource_group_workload != workload`: see the naming-change note above and pass `var.network_watcher_name` to preserve the old name.

## BREAKING CHANGES (vNEXT)

### Subnet API version bump — azapi @2025-03-01 → @2025-05-01

The `azapi_resource.subnet` type string changed from
`Microsoft.Network/virtualNetworks/subnets@2025-03-01` to
`Microsoft.Network/virtualNetworks/subnets@2025-05-01`.

**Why:** Moves NetworkStack onto the latest subnet REST API supported by the
pinned `azapi ~> 2.4` provider (its embedded schema tops out at @2025-05-01;
@2025-07-01 exists in ARM but not yet in the provider) and unlocks the new
`nat_gateway_id` per-subnet field (see below). All properties already written by
the module (`addressPrefixes`, `defaultOutboundAccess`, `networkSecurityGroup`,
`routeTable`, `serviceEndpoints`, `delegations`, `privateEndpointNetworkPolicies`,
`privateLinkServiceNetworkPolicies`) are unchanged between @2025-03-01 and
@2025-05-01 — no body-shape change.

**New feature — `nat_gateway_id`:** Each `subnets` entry now accepts an optional
`nat_gateway_id` (NAT Gateway resource ID) emitted as the `natGateway` property
in the same single PUT. Pair with `default_outbound_access_enabled = false` for
explicit, predictable SNAT egress. Azure forbids a NAT Gateway on GatewaySubnet
and AzureFirewallSubnet.

**Impact on existing state:** `type` on `azapi_resource` is `ForceNew` —
upgrading from a state last applied at @2025-03-01 plans a **destroy + recreate**
of every subnet. For subnets with attached NICs / Private Endpoints the destroy
is blocked by Azure; use the same `state rm` + `import` recipe documented below
(substitute the @2025-05-01 type), then `terraform plan` to confirm a no-op.

## BREAKING CHANGES (v0.2.61)

### Subnet API version bump — azapi @2024-05-01 → @2025-03-01

The `azapi_resource.subnet` type string changed from
`Microsoft.Network/virtualNetworks/subnets@2024-05-01` to
`Microsoft.Network/virtualNetworks/subnets@2025-03-01`.

**Why:** Standardizes NetworkStack on the same Azure REST API version already
used by the sibling modules `Vnet` (v0.2.57) and `SubnetWithNsg` (v0.2.58) for
cross-module consistency (review finding F-7).

**Body shape change:** The `addressPrefix` (singular string) property was
replaced by `addressPrefixes` (array of strings) to match the @2025-03-01
schema. The variable surface is unchanged — callers still supply `cidr` as a
single CIDR string; the module wraps it into a one-element array internally.

**Impact on existing state:**

The `type` attribute on `azapi_resource` is `ForceNew` — Terraform will plan a
**destroy + recreate** of every subnet managed by this module when upgrading from
a state that was last applied at @2024-05-01.

For subnets with attached NICs, Private Link Services, or Private Endpoints the
destroy will be blocked by Azure (resource deletion is rejected while dependants
exist). Perform the state surgery below instead.

**Migration recipe for callers with existing state at @2024-05-01:**

```bash
# 1. Identify each affected subnet in current state:
terraform state list | grep 'azapi_resource.subnet'

# 2. Remove from state (VNet, NSG, RT, and RG resources are unaffected):
terraform state rm 'module.<your_network_stack>.azapi_resource.subnet["<key>"]'

# 3. Re-import the subnet using the Azure resource ID:
terraform import 'module.<your_network_stack>.azapi_resource.subnet["<key>"]' \
  /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>

# 4. Confirm no-op:
terraform plan   # should show no changes for the subnet
```

Repeat steps 2-3 for every subnet entry in the state. The surrounding resources
(VNet, NSGs, Route Table, Network Watcher, peering) require no state surgery.

## What's deliberately not in scope

- **Bidirectional VNet peerings** — the reverse hub->spoke direction must be
  declared on the hub side (connectivity sub). Only the spoke->hub direction is
  self-contained via `hub_peering`.
- **Private Endpoints** — workload-specific lifecycle, deployed alongside the
  PaaS resource they front (Storage, KV, AVD, etc.).
- **Flow logs** — typically lives cross-sub (storage in connectivity hub) +
  optional traffic analytics integration. Use the `FlowLogs` module separately.
- **DNS resolver / Private DNS zones** — connectivity sub concerns, not spoke.
