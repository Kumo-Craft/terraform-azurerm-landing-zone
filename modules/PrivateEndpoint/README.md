# PrivateEndpoint

Creates one or more Azure Private Endpoints to securely connect PaaS services (Key Vault, Storage, ACR, SQL, etc.) to a private virtual network subnet. Supports static IP, custom NIC names, and DNS zone groups.

## Usage

### Standalone

```hcl
module "private_endpoint" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PrivateEndpoint?ref=PrivateEndpoint/v1.0.0"

  location            = "germanywestcentral"
  resource_group_name = "rg-api-prod-gwc-aks"
  subnet_id           = "/subscriptions/.../subnets/snet-api-prod-gwc-pe"

  private_endpoints = {
    acr = {
      name              = "pep-api-prod-gwc-acr-001"
      resource_id       = "/subscriptions/.../registries/crapiprodgwc001"
      subresource_names = ["registry"]
      private_dns_zone_group = {
        private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.azurecr.io"]
      }
    }
    kv = {
      name               = "pep-api-prod-gwc-kv-001"
      resource_id        = "/subscriptions/.../vaults/kv-api-prod-gwc-apim"
      subresource_names  = ["vault"]
      private_ip_address = "10.238.2.10"
    }
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PrivateEndpoint"
}

inputs = {
  location            = include.root.inputs.location
  resource_group_name = dependency.rg.outputs.name
  subnet_id           = dependency.subnet.outputs.subnet_ids["snet-api-prod-gwc-pe"]

  private_endpoints = {
    acr = {
      name              = "pep-api-prod-gwc-acr-001"
      resource_id       = dependency.acr.outputs.id
      subresource_names = ["registry"]
    }
  }

  tags = include.root.inputs.common_tags
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
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| subnet_id | Subnet ID for deploying PEs | `string` | -- | Yes |
| private_endpoints | Map of PE configurations. Key is arbitrary. | `map(object({...}))` | -- | Yes |
| tags | Common tags for all PEs | `map(string)` | `{}` | No |

### Private Endpoint Object

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| name | `string` | Yes | -- | Private Endpoint name |
| resource_id | `string` | Yes | -- | Target Azure resource ID |
| subresource_names | `list(string)` | Yes | -- | Subresources (e.g. `["vault"]`, `["blob"]`, `["registry"]`) |
| is_manual_connection | `bool` | No | `false` | Manual connection requiring approval |
| request_message | `string` | No | -- | Message for manual connections (required if manual) |
| private_ip_address | `string` | No | -- | Static private IP |
| member_name | `string` | No | `"default"` | Member name for IP config |
| custom_network_interface_name | `string` | No | -- | Custom NIC name |
| private_dns_zone_group | `object` | No | -- | DNS zone group (name + zone IDs) |
| tags | `map(string)` | No | `{}` | Endpoint-specific tags |

## Outputs

| Name | Description |
|------|-------------|
| resources | Map of key => complete PE resource object |
| ids | Map of key => PE ID |
| private_ip_addresses | Map of key => private IP address |

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

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region for Private Endpoints | `string` | n/a | yes |
| private\_endpoints | A map of Private Endpoint configurations. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>Each entry must set EXACTLY ONE of `resource_id` or `resource_alias`:<br>- `resource_id`    targets a regular Azure resource (Key Vault, Storage<br>  Account, etc.) and uses `private_connection_resource_id` at the<br>  provider level. Requires `subresource_names` (e.g. ["vault"]).<br>- `resource_alias` targets a Private Link Service by alias string<br>  (e.g. third-party PLS, cross-subscription endpoints) and uses<br>  `private_connection_resource_alias` at the provider level.<br>  `subresource_names` is typically empty for alias-based connections.<br><br>Object fields:<br>- `name`                           - (Required) Private Endpoint name.<br>- `resource_id`                    - (Optional) Target Azure resource ID. Mutually exclusive with `resource_alias`.<br>- `resource_alias`                 - (Optional) Private Link Service alias. Mutually exclusive with `resource_id`.<br>- `subresource_names`              - (Optional) Subresources to expose (e.g. ["vault"], ["blob"]). Required when `resource_id` is set; ignored for alias-based PEs.<br>- `is_manual_connection`           - (Optional) Manual connection requiring approval. Defaults to false.<br>- `request_message`                - (Optional) Message for manual connections. NOTE: this string appears in plan output — do NOT embed credentials or tokens.<br>- `private_ip_address`             - (Optional) Static private IP address.<br>- `member_name`                    - (Optional) Member name for IP config. Defaults to "default".<br>- `custom_network_interface_name`  - (Optional) Custom NIC name.<br>- `private_dns_zone_group`         - (Optional) DNS zone group configuration.<br>- `tags`                           - (Optional) Tags specific to this endpoint. | <pre>map(object({<br>    name                          = string<br>    resource_id                   = optional(string)<br>    resource_alias                = optional(string)<br>    subresource_names             = optional(list(string), [])<br>    is_manual_connection          = optional(bool, false)<br>    request_message               = optional(string)<br>    private_ip_address            = optional(string)<br>    member_name                   = optional(string, "default")<br>    custom_network_interface_name = optional(string)<br>    private_dns_zone_group = optional(object({<br>      name                 = optional(string, "default")<br>      private_dns_zone_ids = list(string)<br>    }))<br>    tags = optional(map(string), {})<br>  }))</pre> | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| subnet\_id | Subnet ID for deploying Private Endpoints | `string` | n/a | yes |
| tags | Common tags to apply to all Private Endpoints | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of endpoint key => Private Endpoint ID |
| private\_ip\_addresses | Map of endpoint key => private IP address |
| resources | Map of endpoint key => complete Private Endpoint resource object |
<!-- END_TF_DOCS -->
