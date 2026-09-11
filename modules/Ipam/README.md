# Ipam

Centralised **IP Address Management** on **Azure Virtual Network Manager (AVNM)**: an (optional) Network Manager plus a **hierarchy of IPAM pools** and fixed **static CIDR** reservations. Pools hand out non-overlapping address space to VNets/subnets and let you track utilisation from one place, instead of tracking CIDRs in a spreadsheet.

## Why AVNM IPAM (Microsoft guidance)

Grounded in Microsoft docs ([How IPAM works](https://learn.microsoft.com/azure/virtual-network-manager/how-to-manage-ip-addresses-network-manager), [AVNM concepts](https://learn.microsoft.com/azure/virtual-network-manager/concept-ip-address-management)):

- **One source of truth.** An IPAM pool is a collection of CIDR ranges; AVNM prevents pools from overlapping and reports allocation/utilisation, so address planning lives in Azure rather than a spreadsheet.
- **Hierarchy.** Pools nest (a root supernet → child pools) so you can delegate a slice of the supernet to a region/landing-zone while the parent still sees usage. AVNM supports several layers; **this module models the common two tiers** (root → child) because Terraform cannot order deeper self-referential chains within one resource set — see *Design notes*.
- **Always available.** IPAM is available on any Network Manager instance regardless of its `scope_accesses` (Connectivity / SecurityAdmin / Routing) — the module keeps `scope_accesses` minimal (`["Connectivity"]`) by default.
- **Static CIDRs.** Reserve a fixed range out of a pool either by explicit prefix (`address_prefixes`) or by asking AVNM to allocate a power-of-two block (`number_of_ip_addresses_to_allocate`) — exactly one per reservation.
- **Enforcement is separate.** Assigning pool space to a VNet and *enforcing* that VNets only use pool-allocated space is done via VNet association / Azure Policy downstream — out of scope here (this module owns the pools, not the consumers).

## Usage

### Create the AVNM + a two-tier pool hierarchy

```hcl
module "ipam" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/Ipam?ref=v0.3.0"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-ipam"

  # AVNM scope — tenant-wide via a management group (or subscription_ids)
  network_manager_scope = {
    management_group_ids = ["/providers/Microsoft.Management/managementGroups/mg-root"]
  }

  pools = {
    # Root supernet
    root = {
      address_prefixes = ["10.0.0.0/8"]
      display_name     = "Corp supernet"
    }
    # Child pool carved from the root, with two fixed reservations
    hub = {
      address_prefixes = ["10.0.0.0/16"]
      parent_pool_key  = "root"
      static_cidrs = {
        firewall = { address_prefixes = ["10.0.0.0/26"] }          # explicit range
        bastion  = { number_of_ip_addresses_to_allocate = "64" }   # auto-allocated /26
      }
    }
  }

  tags = { Environment = "Production" }
}
```

### Bring-your-own AVNM (attach pools to an existing Network Manager)

```hcl
module "ipam" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/Ipam?ref=v0.3.0"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-ipam" # unused when not creating the AVNM

  create_network_manager      = false
  existing_network_manager_id = module.connectivity.network_manager_id

  pools = {
    root = { address_prefixes = ["10.0.0.0/8"] }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/Ipam"
}

inputs = {
  subscription_acronym  = include.sub.locals.subscription_acronym
  environment           = include.root.inputs.environment
  region_code           = include.root.inputs.region_code
  location              = include.root.inputs.location
  resource_group_name   = dependency.rg.outputs.name
  network_manager_scope = { management_group_ids = [dependency.mg.outputs.root_id] }
  pools                 = include.env.locals.ipam_pools
  tags                  = include.root.inputs.common_tags
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `subscription_acronym` | `string` | — (required) | Subscription acronym (e.g. `con`). |
| `environment` | `string` | — (required) | Environment (`prod`/`nprd`). |
| `region_code` | `string` | — (required) | Region short code (e.g. `gwc`). |
| `workload` | `string` | `"01"` | Workload/instance suffix. |
| `location` | `string` | — (required) | Azure region for the AVNM + pools (ForceNew on pools). |
| `resource_group_name` | `string` | — (required) | RG hosting the AVNM (used only when `create_network_manager = true`). |
| `create_network_manager` | `bool` | `true` | Create a dedicated AVNM, or attach to an existing one. |
| `existing_network_manager_id` | `string` | `null` | Existing AVNM id — **required** when `create_network_manager = false`. |
| `network_manager_name` | `string` | `null` | Override AVNM name (null = `nm-{acr}-{env}-{region}-{workload}`). |
| `network_manager_description` | `string` | `"IPAM …"` | AVNM description. |
| `network_manager_scope` | `object({ management_group_ids, subscription_ids })` | `{}` | Scope managed by the AVNM. At least one entry required when creating. |
| `network_manager_scope_accesses` | `list(string)` | `["Connectivity"]` | Allowed config types (`Connectivity`/`SecurityAdmin`/`Routing`). IPAM works regardless. |
| `pools` | `map(object(...))` | `{}` | IPAM pools keyed by a local key (see below). |
| `tags` | `map(string)` | `{}` | Tags for the AVNM and pools. |

### `pools` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `address_prefixes` | `list(string)` | — (required) | CIDR(s) owned by the pool (ForceNew). |
| `name` | `string` | `null` | Name override (null = `ipam-{key}-{acr}-{env}-{region}-{workload}`). |
| `display_name` | `string` | `null` | Portal display name (null = pool key). |
| `description` | `string` | `null` | Pool description. |
| `parent_pool_key` | `string` | `null` | Key of the parent (root) pool — makes this a child pool. |
| `static_cidrs` | `map(object(...))` | `{}` | Fixed reservations: each sets **either** `address_prefixes` **or** `number_of_ip_addresses_to_allocate` (power-of-two string), not both. |

## Outputs

| Name | Description |
|------|-------------|
| `network_manager_id` | AVNM id hosting the pools (created or existing). |
| `network_manager_name` | AVNM name when created here (null when BYO). |
| `ipam_pool_ids` | Map of pool key → pool id (roots + children). |
| `ipam_pool_names` | Map of pool key → pool name. |
| `static_cidr_ids` | Map of `poolKey/cidrKey` → static CIDR id. |

## Design notes

- **Two-tier hierarchy.** `parent_pool_name` on `azurerm_network_manager_ipam_pool` is a plain string, and the API rejects a child whose parent doesn't exist yet. Terraform forbids a `for_each` resource from referencing its own instances, so the module splits pools into a **root** block and a **child** block: the child references the root's `name` attribute, giving a real dependency edge that orders creation correctly. A `parent_pool_key` must therefore point at a **root** pool (validated). Deeper nesting (grandchildren) would require ordered self-reference Terraform can't express in one set — manage extra layers out-of-band if you truly need the AVNM maximum of 7 layers.
- **Secure/minimal by default.** `scope_accesses = ["Connectivity"]` (least surface; IPAM is independent of it). No public-surface settings apply to AVNM/IPAM.

## Out of scope (handle downstream / ops)

- **VNet association & Policy enforcement** — associating a pool with VNets and enforcing that address space is drawn only from pools ([manage IP addresses](https://learn.microsoft.com/azure/virtual-network-manager/how-to-manage-ip-addresses-network-manager)).
- **Deeper than two tiers** — see *Design notes*.
- **`Microsoft.Network` registration at management-group scope** — required before an MG-scoped AVNM deploys ([AVNM scope](https://learn.microsoft.com/azure/virtual-network-manager/concept-network-manager-scope#scope)).

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: slug naming, two-tier hierarchy wiring, BYO AVNM, both static-CIDR forms, and the validators (BYO id required, scope required, bad/self/three-tier parent, static-CIDR XOR). Run: `terraform init -backend=false && terraform test`.
