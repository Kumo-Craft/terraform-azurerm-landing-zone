# Vnet

Creates an Azure Virtual Network with configurable address spaces, DNS servers, optional DDoS protection, management lock, and optional inline subnets with NSG/RT/NAT associations.

> **Policy compliance note** — Inline subnets are created via `azapi_resource` so the subnet, NSG, route table, NAT Gateway, service endpoints and delegations land in **one** atomic Azure API call. The classic 2-step pattern (`azurerm_subnet` then `azurerm_subnet_*_association`) is rejected by the Azure Policy *"Subnets must have a Network Security Group"* (Deny) because the subnet briefly exists without an NSG. This module is policy-compliant by construction. The schema is unchanged — `delegations[].service_delegation.actions` is accepted but no longer needed (Azure auto-populates actions from the service name).
>
> **Already-deployed callers**: see [MIGRATION.md](MIGRATION.md) for the `state rm` + `import` procedure. Without it, the next plan will want to destroy/recreate inline subnets — Azure rejects this when the subnet has dependants.

## BREAKING CHANGES

### v0.2.57 — Delegation shape change (SOFT BREAKING)

The per-subnet delegation object in `var.subnets[*].delegations` changed from the nested `service_delegation` shape to a flat `{ name, service_name }` shape. This aligns with `SubnetWithNsg`.

**Migration recipe** (variable-only change — no `moved` block needed; state is keyed by subnet name):

```hcl
# Before (v0.2.53 and earlier):
subnets = [
  {
    name             = "snet-api-prod-gwc-nodes"
    address_prefixes = ["10.238.1.0/24"]
    delegations = [
      {
        name = "aks-delegation"
        service_delegation = {
          name    = "Microsoft.ContainerService/managedClusters"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
    ]
  }
]

# After (v0.2.57+):
subnets = [
  {
    name             = "snet-api-prod-gwc-nodes"
    address_prefixes = ["10.238.1.0/24"]
    delegations = [
      {
        name         = "aks-delegation"
        service_name = "Microsoft.ContainerService/managedClusters"
      }
    ]
  }
]
```

> **Note**: `actions` was previously silently ignored (Azure auto-populates them from `service_name`). The new shape makes this explicit by removing the `actions` field entirely.

## Usage

### Standalone

```hcl
module "vnet" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/Vnet?ref=v0.2.57"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "spoke"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-network"

  address_space = ["10.238.0.0/21"]
  dns_servers   = ["10.238.200.68"]

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Terragrunt (with inline subnets)

```hcl
terraform {
  source = "${get_repo_root()}/modules/Vnet"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "spoke"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  address_space        = include.sub.locals.networks.corp_apimanager.address_space
  dns_servers          = [dependency.dns_resolver.outputs.inbound_endpoint_ip]

  subnets = [
    {
      name             = "snet-api-prod-gwc-nodes"
      address_prefixes = ["10.238.1.0/24"]
      nsg_id           = dependency.nsg.outputs.ids["nodes"]
      route_table_id   = dependency.rt.outputs.id
    }
  ]

  tags = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| azapi | ~> 2.4 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Explicit VNet name. If null, computed. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, con, api) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (e.g. hub, spoke) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| address_space | VNet CIDR address space | `list(string)` | `null` | No |
| dns_servers | Custom DNS server IPs | `list(string)` | `null` | No |
| enable_ddos_protection | Enable DDoS Standard protection | `bool` | `false` | No |
| ddos_protection_plan_id | DDoS Protection Plan ID | `string` | `null` | No |
| ip_address_pool | Azure IPAM pool configuration | `object({...})` | `null` | No |
| encryption_enforcement | VNet-level encryption: `AllowUnencrypted` or `DropUnencrypted`. null = disabled. | `string` | `null` | No |
| flow_timeout_in_minutes | Idle flow timeout (4-30 minutes). null = Azure default (4 min). | `number` | `null` | No |
| subnets | Inline subnets. Each delegation uses `{ name, service_name }` — see BREAKING CHANGES. | `list(object({...}))` | `[]` | No |
| lock | Management lock (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| role_assignments | Map of role assignments at VNet scope | `map(object({...}))` | `{}` | No |
| tags | Tags to assign | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | VNet resource ID |
| name | VNet name |
| resource_group_name | Resource group name |
| location | Azure region |
| tags | Tags applied |
| resource | Complete VNet resource object |
| subnet_ids | Map of subnet name => subnet ID |
| subnet_names | Map of subnet name => subnet name |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.subnet](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| address\_space | VNet CIDR address space (e.g. ["10.238.0.0/22"]) | `list(string)` | `null` | no |
| ddos\_protection\_plan\_id | DDoS Protection Plan ID to associate with the VNet | `string` | `null` | no |
| dns\_servers | Custom DNS server IPs. If null or empty, uses Azure default DNS. | `list(string)` | `null` | no |
| enable\_ddos\_protection | Enable DDoS Standard protection on the VNet. Requires ddos\_protection\_plan\_id. | `bool` | `false` | no |
| encryption\_enforcement | Optional VNet-level encryption enforcement (VM-to-VM confidential traffic, GA in Azure). 'AllowUnencrypted' = encrypt where possible but allow unencrypted ; 'DropUnencrypted' = require encryption (drops non-encrypted traffic). Set to null to disable VNet encryption (default Azure behavior). | `string` | `null` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| flow\_timeout\_in\_minutes | Idle flow timeout for the VNet in minutes (4-30). null = Azure default (4 minutes). Useful for hub VNets with long-lived TCP sessions (e.g. AKS, NFS). | `number` | `null` | no |
| ip\_address\_pool | Optional Azure IPAM pool configuration for the VNet | <pre>object({<br>    id                     = string<br>    number_of_ip_addresses = number<br>  })</pre> | `null` | no |
| lock | Controls the Resource Lock configuration for this resource.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit VNet name. If null, computed from naming components. | `string` | `null` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the Virtual Network scope. Common patterns: 'Network Contributor' for AKS SP, 'Reader' for Platform team. Default principal\_type='ServicePrincipal' (network resources rarely user-assigned). | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subnets | Optional list of subnets to create within this VNet. When empty, use the separate SubnetWithNsg module. | <pre>list(object({<br>    name                              = string<br>    address_prefixes                  = optional(list(string))<br>    nsg_id                            = optional(string)<br>    service_endpoints                 = optional(list(string))<br>    route_table_id                    = optional(string)<br>    nat_gateway_id                    = optional(string)<br>    ip_address_pool                   = optional(object({ id = string, number_of_ip_addresses = number }))<br>    private_endpoint_network_policies = optional(string)<br>    default_outbound_access_enabled   = optional(bool, false)<br>    delegations = optional(list(object({<br>      name         = string<br>      service_name = string<br>    })), [])<br>  }))</pre> | `[]` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, con, api) | `string` | `null` | no |
| tags | Tags to assign to the VNet | `map(string)` | `{}` | no |
| workload | Workload name for naming convention (e.g. hub, spoke) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The VNet resource ID |
| location | The VNet Azure region |
| name | The VNet name |
| resource | The complete Virtual Network resource object |
| resource\_group\_name | The VNet resource group name |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
| subnet\_ids | Map of subnet name => subnet ID |
| subnet\_names | Map of subnet name => subnet name |
| tags | The tags applied to the VNet |
<!-- END_TF_DOCS -->
