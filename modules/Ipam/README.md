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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_network_manager.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_manager) | resource |
| [azurerm_network_manager_ipam_pool.child](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_manager_ipam_pool) | resource |
| [azurerm_network_manager_ipam_pool.root](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_manager_ipam_pool) | resource |
| [azurerm_network_manager_ipam_pool_static_cidr.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_manager_ipam_pool_static_cidr) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment (prod/nprd). | `string` | n/a | yes |
| location | Azure region for the Network Manager and its IPAM pools (ForceNew on the pools). | `string` | n/a | yes |
| region\_code | Region short code (e.g. 'gwc'). | `string` | n/a | yes |
| resource\_group\_name | Resource group hosting the Network Manager (used only when create\_network\_manager = true). | `string` | n/a | yes |
| subscription\_acronym | Subscription acronym (e.g. 'con'). | `string` | n/a | yes |
| create\_network\_manager | Create a dedicated Network Manager to host the IPAM pools. Set false to attach the pools to an existing AVNM (existing\_network\_manager\_id). | `bool` | `true` | no |
| existing\_network\_manager\_id | Resource id of an existing Network Manager to attach the IPAM pools to. Required when create\_network\_manager = false. | `string` | `null` | no |
| network\_manager\_description | Description of the Network Manager. | `string` | `"IPAM — centralised IP address management (AVNM)."` | no |
| network\_manager\_name | Override for the Network Manager name. Null = derive from the Naming submodule (nm-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| network\_manager\_scope | Scope the Network Manager manages. Provide at least one management group id or subscription id when create\_network\_manager = true. Management-group scope requires Microsoft.Network registered at that MG. | <pre>object({<br>    management_group_ids = optional(list(string), [])<br>    subscription_ids     = optional(list(string), [])<br>  })</pre> | `{}` | no |
| network\_manager\_scope\_accesses | Configuration deployment types allowed on the Network Manager. IPAM is available on any AVNM regardless of this list; keep it minimal. Allowed: Connectivity, SecurityAdmin, Routing. | `list(string)` | <pre>[<br>  "Connectivity"<br>]</pre> | no |
| pools | IPAM pools keyed by a stable local key. Reference a parent pool via parent\_pool\_key to build the hierarchy (root + up to 7 layers). static\_cidrs reserves fixed ranges: set EITHER address\_prefixes OR number\_of\_ip\_addresses\_to\_allocate, not both. | <pre>map(object({<br>    name             = optional(string) # override; null = ipam-{key}-{acr}-{env}-{region}-{workload}<br>    display_name     = optional(string) # portal display name; null = pool key<br>    description      = optional(string)<br>    address_prefixes = list(string)                         # CIDR(s) owned by this pool (ForceNew)<br>    parent_pool_key  = optional(string)                     # key of the parent pool in this same map (hierarchy)<br>    static_cidrs = optional(map(object({                    # carve fixed sub-CIDRs out of the pool<br>      name                               = optional(string) # override; null = static CIDR key<br>      address_prefixes                   = optional(list(string))<br>      number_of_ip_addresses_to_allocate = optional(string) # power-of-2 count; auto-allocated from the pool<br>    })), {})<br>  }))</pre> | `{}` | no |
| tags | Tags applied to the Network Manager and IPAM pools. | `map(string)` | `{}` | no |
| workload | Workload/instance suffix for naming. | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| ipam\_pool\_ids | Map of pool key => IPAM pool resource id (root and child pools merged). |
| ipam\_pool\_names | Map of pool key => IPAM pool name. |
| network\_manager\_id | Resource id of the Network Manager hosting the IPAM pools (created here or the existing one passed in). |
| network\_manager\_name | Name of the Network Manager when created by this module (null when bringing your own). |
| static\_cidr\_ids | Map of 'poolKey/cidrKey' => static CIDR resource id. |
<!-- END_TF_DOCS -->
