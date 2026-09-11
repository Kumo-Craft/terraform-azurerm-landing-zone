# NSG

Creates one or more Azure Network Security Groups in a single module call. Each NSG is named using the `nsg-{subscription_acronym}-{environment}-{region_code}-{key}` convention and supports a full set of security rules with input validation.

## Usage

### Standalone

```hcl
module "nsg" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/NSG?ref=v0.2.4"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-network"

  nsgs = {
    nodes = [
      {
        name                       = "allow-https-inbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "10.238.0.0/16"
        destination_address_prefix = "*"
      }
    ]
    pe = []
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/NSG"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  tags                 = include.root.inputs.common_tags

  nsgs = {
    nodes = []
    pods  = []
    pe    = []
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
| subscription_acronym | Subscription acronym (e.g. con, api) | `string` | -- | Yes |
| environment | Environment (e.g. prod, nprd) | `string` | -- | Yes |
| region_code | Region code (e.g. gwc, weu) | `string` | -- | Yes |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group where NSGs are created | `string` | -- | Yes |
| workload | Workload segment of the house naming convention. Present for symmetry with other modules and Terragrunt `include.root.inputs.workload` wiring, but **intentionally NOT used in the NSG name** — this module is map-shaped and uses each map key as the per-NSG workload segment. Forwarded to the Naming submodule but the produced names rely on the map key, not on this value. | `string` | `null` | No |
| nsgs | Map of NSGs to create. Key = workload suffix, value = list of security rules. | `map(list(object({...})))` | -- | Yes |
| tags | Tags to apply to all NSGs | `map(string)` | `{}` | No |

### Security Rule Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | `string` | Yes | Rule name |
| priority | `number` | Yes | Priority (100-4096) |
| direction | `string` | Yes | `Inbound` or `Outbound` |
| access | `string` | Yes | `Allow` or `Deny` |
| protocol | `string` | Yes | `Tcp`, `Udp`, `Icmp`, `Esp`, `Ah`, or `*` |
| source_port_range | `string` | No | Single source port or range |
| destination_port_range | `string` | No | Single destination port or range |
| source_address_prefix | `string` | No | Single source CIDR |
| destination_address_prefix | `string` | No | Single destination CIDR |
| source_port_ranges | `list(string)` | No | Multiple source ports |
| destination_port_ranges | `list(string)` | No | Multiple destination ports |
| source_address_prefixes | `list(string)` | No | Multiple source CIDRs |
| destination_address_prefixes | `list(string)` | No | Multiple destination CIDRs |
| source_application_security_group_ids | `list(string)` | No | Source ASG IDs |
| destination_application_security_group_ids | `list(string)` | No | Destination ASG IDs |
| description | `string` | No | Rule description |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of workload key => NSG ID |
| names | Map of workload key => NSG name |
| resources | Map of workload key => complete NSG resource object |

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
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_network_security_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment (e.g. prod, nprd) | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| nsgs | Map of NSGs to create. Key = workload suffix (used in naming: nsg-{sub}-{env}-{region}-{key}).<br>Value = list of security rules for that NSG.<br><br>Each security rule supports:<br>- `name`                  - (Required) Rule name.<br>- `priority`              - (Required) Priority between 100 and 4096.<br>- `direction`             - (Required) "Inbound" or "Outbound".<br>- `access`                - (Required) "Allow" or "Deny".<br>- `protocol`              - (Required) "Tcp", "Udp", "Icmp", "Esp", "Ah", or "*".<br>- `source_port_range`     / `source_port_ranges`      - Source port(s).<br>- `destination_port_range`/ `destination_port_ranges`  - Destination port(s).<br>- `source_address_prefix` / `source_address_prefixes`  - Source CIDR(s).<br>- `destination_address_prefix` / `destination_address_prefixes` - Destination CIDR(s).<br>- `source_application_security_group_ids`      - (Optional) Source ASG IDs.<br>- `destination_application_security_group_ids` - (Optional) Destination ASG IDs.<br>- `description`           - (Optional) Rule description. | <pre>map(list(object({<br>    name                                       = string<br>    priority                                   = number<br>    direction                                  = string<br>    access                                     = string<br>    protocol                                   = string<br>    source_port_range                          = optional(string)<br>    destination_port_range                     = optional(string)<br>    source_address_prefix                      = optional(string)<br>    destination_address_prefix                 = optional(string)<br>    source_port_ranges                         = optional(list(string))<br>    destination_port_ranges                    = optional(list(string))<br>    source_address_prefixes                    = optional(list(string))<br>    destination_address_prefixes               = optional(list(string))<br>    source_application_security_group_ids      = optional(list(string))<br>    destination_application_security_group_ids = optional(list(string))<br>    description                                = optional(string)<br>  })))</pre> | n/a | yes |
| region\_code | Region code (e.g. gwc, weu) | `string` | n/a | yes |
| resource\_group\_name | Resource group where NSGs are created | `string` | n/a | yes |
| subscription\_acronym | Subscription acronym (e.g. con, api, mgm) | `string` | n/a | yes |
| tags | Tags to apply to all NSGs | `map(string)` | `{}` | no |
| workload | Workload segment of the house naming convention. Present for symmetry<br>with other modules and Terragrunt `include.root.inputs.workload` wiring,<br>but **intentionally NOT used in the NSG name** — this module is<br>map-shaped (`var.nsgs`) and uses each map key as the per-NSG workload<br>segment (final name: `nsg-{acr}-{env}-{region}-{key}`). Callers can<br>pass this variable safely; it is forwarded to the Naming submodule but<br>the produced names rely on the map key, not on this value.<br><br>Provided so Terragrunt configs don't need a NSG-specific override of<br>the standard `inputs.workload` pattern. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of workload key => NSG ID |
| names | Map of workload key => NSG name |
| resources | Map of workload key => complete NSG resource object |
<!-- END_TF_DOCS -->
