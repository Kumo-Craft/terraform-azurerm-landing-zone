# SubnetWithNsg

Creates one or more Azure subnets with NSG attached in a single API call using `azapi_resource`. This is required when Azure Policy "Subnets must have a Network Security Group" is set to Deny, as the standard `azurerm_subnet` + `azurerm_subnet_network_security_group_association` two-step approach is blocked.

**Important:** Output keys in `subnet_ids` use the **full subnet name** (e.g. `snet-api-prod-gwc-nodes`), not short names.

## BREAKING CHANGES

### v0.2.54 — `address_prefix` renamed to `address_prefixes` (string → list(string))

The per-subnet `address_prefix = string` field has been replaced by `address_prefixes = list(string)` to enable dual-stack (IPv4 + IPv6) and multi-CIDR subnets. The ARM API field `addressPrefixes` (array) is now emitted instead of the legacy scalar `addressPrefix`.

Migration recipe for every subnet entry:

```hcl
# Before (v0.2.53 and earlier)
{
  name           = "snet-api-prod-gwc-nodes"
  address_prefix = "10.238.1.0/24"
}

# After (v0.2.54+)
{
  name             = "snet-api-prod-gwc-nodes"
  address_prefixes = ["10.238.1.0/24"]
}
```

## Usage

### Standalone

```hcl
module "subnet" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SubnetWithNsg?ref=v0.2.58"

  virtual_network_id = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"

  subnets = [
    {
      name             = "snet-api-prod-gwc-nodes"
      address_prefixes = ["10.238.1.0/24"]
      nsg_id           = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-nodes"
      route_table_id   = "/subscriptions/.../routeTables/rt-api-prod-gwc-spoke"
    },
    {
      name             = "snet-api-prod-gwc-pe"
      address_prefixes = ["10.238.2.0/24"]
      nsg_id           = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-pe"
      route_table_id   = "/subscriptions/.../routeTables/rt-api-prod-gwc-spoke"
    }
  ]
}
```

### With per-subnet lock and role assignment

```hcl
module "subnet" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SubnetWithNsg?ref=v0.2.58"

  virtual_network_id = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"

  subnets = [
    {
      name             = "snet-api-prod-gwc-nodes"
      address_prefixes = ["10.238.1.0/24"]
      nsg_id           = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-nodes"

      # Lock only this subnet — others remain unlocked
      lock = {
        kind = "CanNotDelete"
        name = "lock-nodes-subnet"
      }

      # Grant AKS service principal Network Contributor on this subnet only
      role_assignments = {
        aks_sp = {
          role_definition_id_or_name = "Network Contributor"
          principal_id               = "00000000-0000-0000-0000-000000000001"
          principal_type             = "ServicePrincipal"
        }
      }
    },
    {
      name             = "snet-api-prod-gwc-pe"
      address_prefixes = ["10.238.2.0/24"]
      nsg_id           = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-pe"
    }
  ]
}
```

### With IPAM pool allocation

```hcl
module "subnet" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SubnetWithNsg?ref=v0.2.58"

  virtual_network_id = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"

  subnets = [
    {
      name  = "snet-api-prod-gwc-nodes"
      nsg_id = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-nodes"

      # IPAM allocates address_prefixes automatically — omit address_prefixes when using this
      ip_address_pool = {
        id                     = "/subscriptions/.../networkManagers/.../ipamPools/pool-gwc-prod"
        number_of_ip_addresses = 256
      }
    }
  ]
}
```

### Sprint 4 features — NAT Gateway, service endpoints, multi-delegation, per-subnet lock and RBAC

```hcl
module "subnet" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SubnetWithNsg?ref=v0.2.58"

  virtual_network_id = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"

  subnets = [
    {
      name             = "snet-api-prod-gwc-aks-nodes"
      address_prefixes = ["10.238.1.0/24"]
      nsg_id           = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-nodes"
      route_table_id   = "/subscriptions/.../routeTables/rt-api-prod-gwc-spoke"

      # Sprint 4: NAT Gateway association
      nat_gateway_id = "/subscriptions/.../natGateways/ng-api-prod-gwc"

      # Sprint 4: Service endpoints
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]

      # Sprint 4: Multi-delegation using the preferred delegations field (flat {name, service_name} shape)
      delegations = [
        {
          name         = "aks-delegation"
          service_name = "Microsoft.ContainerService/managedClusters"
        }
      ]

      # Per-subnet management lock
      lock = {
        kind = "CanNotDelete"
        name = "lock-aks-nodes-subnet"
      }

      # Per-subnet RBAC
      role_assignments = {
        aks_sp = {
          role_definition_id_or_name = "Network Contributor"
          principal_id               = "00000000-0000-0000-0000-000000000001"
          principal_type             = "ServicePrincipal"
        }
      }
    },
    {
      name              = "snet-api-prod-gwc-aks-apiserver"
      address_prefixes  = ["10.238.2.0/24"]
      nsg_id            = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-apiserver"

      # Sprint 4: AKS API server VNet injection delegation
      delegations = [
        {
          name         = "aks-apiserver-delegation"
          service_name = "Microsoft.ContainerService/managedClusters"
        }
      ]
    },
    {
      name             = "snet-api-prod-gwc-pe"
      address_prefixes = ["10.238.3.0/24"]
      nsg_id           = "/subscriptions/.../networkSecurityGroups/nsg-api-prod-gwc-pe"

      # Private Endpoint subnets must have Disabled (default) to allow PE deployments
      private_endpoint_network_policies = "Disabled"
    }
  ]
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/SubnetWithNsg"
}

inputs = {
  virtual_network_id = dependency.network.outputs.id

  subnets = [
    {
      name             = include.sub.locals.networks.corp_apimanager.subnets.nodes.name
      address_prefixes = [include.sub.locals.networks.corp_apimanager.subnets.nodes.cidr]
      nsg_id           = dependency.nsg.outputs.ids["nodes"]
      route_table_id   = dependency.rt.outputs.id
    },
    {
      name             = include.sub.locals.networks.corp_apimanager.subnets.apiserver.name
      address_prefixes = [include.sub.locals.networks.corp_apimanager.subnets.apiserver.cidr]
      nsg_id           = dependency.nsg.outputs.ids["apiserver"]
      route_table_id   = dependency.rt.outputs.id
      delegation = {
        name         = "aks-apiserver"
        service_name = "Microsoft.ContainerService/managedClusters"
      }
    }
  ]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| virtual_network_id | Full resource ID of the virtual network | `string` | -- | Yes |
| subnets | List of subnets to create with NSG in a single API call | `list(object({...}))` | -- | Yes |

### Subnet Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | `string` | Yes | Subnet name (full name, e.g. snet-api-prod-gwc-nodes) |
| address_prefixes | `list(string)` | Conditional | List of CIDR blocks (e.g. `["10.238.1.0/24"]`). Required when `ip_address_pool` is not set. Supports dual-stack and multi-CIDR. **Replaces `address_prefix`** |
| nsg_id | `string` | No | NSG resource ID to associate |
| route_table_id | `string` | No | Route Table resource ID to associate |
| nat_gateway_id | `string` | No | NAT Gateway resource ID. Forbidden on AzureFirewallSubnet, GatewaySubnet, AzureBastionSubnet |
| service_endpoints | `list(string)` | No | Service endpoints (e.g. `["Microsoft.Storage", "Microsoft.KeyVault"]`). Default: `[]` |
| private_endpoint_network_policies | `string` | No | `Enabled`, `Disabled`, `NetworkSecurityGroupEnabled`, `RouteTableEnabled`. Default: `Disabled` (recommended for PE-hosting subnets) |
| default_outbound_access_enabled | `bool` | No | Enable default outbound access. Default: `false` (best practice — outbound through NAT/firewall instead) |
| ip_address_pool | `object({ id = string, number_of_ip_addresses = number })` | No | Azure IPAM pool allocation. When set, `address_prefixes` can be omitted (Azure assigns CIDRs from the pool) |
| delegation | `object` | No | **DEPRECATED** — use `delegations`. Single service delegation. Merged with `delegations` if both set |
| delegations | `list(object)` | No | List of service delegations. Most subnets need 0 or 1 |
| lock | `object({ kind = string, name = optional(string) })` | No | Management lock scoped to this subnet only. `kind` must be `CanNotDelete` or `ReadOnly` |
| role_assignments | `map(object({...}))` | No | Map of role assignments scoped to this subnet. Default: `{}` |

#### role_assignments entry

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| role_definition_id_or_name | `string` | -- | Built-in role name or full role definition ID |
| principal_id | `string` | -- | Object ID of the principal |
| principal_type | `string` | `"ServicePrincipal"` | `User`, `Group`, `ServicePrincipal`, `ForeignGroup`, or `Device` |
| condition | `string` | `null` | ABAC condition expression |
| condition_version | `string` | `null` | `"1.0"` or `"2.0"` (required when condition is set) |
| description | `string` | `null` | Free-text description |
| skip_service_principal_aad_check | `bool` | `false` | Skip AAD existence check (useful on first apply) |

## Outputs

| Name | Description |
|------|-------------|
| subnet_ids | Map of full subnet name => subnet ID |
| resources | Map of full subnet name => complete azapi_resource object |
| lock_ids | Map of subnet name => management lock ID (only entries where a lock was configured) |
| role_assignment_ids | Map of `<subnet_name>.<assignment_key>` => role assignment resource ID |
