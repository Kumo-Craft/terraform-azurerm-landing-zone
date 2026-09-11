# DomainServices

Deploys a **Microsoft Entra Domain Services** managed domain (`Microsoft.AAD/domainServices`) — managed AD DS (domain-join, LDAP, Kerberos/NTLM, group policy) with **no domain controllers to run**. One managed domain + optional Resource Lock. **User Forest** mode.

The module owns **only** the `azurerm_active_directory_domain_service` resource and its lock. It does **not** create the tenant-level prerequisites — those are out-of-band (see below).

## Out-of-band prerequisites (NOT managed here)

Provision these once, before applying the module ([tutorial](https://learn.microsoft.com/entra/identity/domain-services/tutorial-create-instance)):

1. **Resource Provider** — register `Microsoft.AAD` on the target subscription.
2. **Service Principal** — the *Domain Controller Services* published app (`2565bd9d-da50-47d4-8b85-4c97f669dc36`) must have a service principal in the tenant (create manually — it doesn't exist by default).
3. **Group** — an *AAD DC Administrators* security group in Entra ID.
4. **Password hashes** — cloud users must reset their password; hybrid tenants must enable legacy hash sync in Entra Connect (so NTLM/Kerberos hashes exist).
5. **Networking** — the replica subnet needs an NSG allowing `AzureActiveDirectoryDomainServices` inbound (443/5986), plus LDAPS (636) if `secure_ldap` is enabled.

## Naming

Via the [`Naming`](../Naming/) submodule with the house prefix `aadds-`: `aadds-{acronym}-{env}-{region}-{workload}` (workload default `domain`) → e.g. **`aadds-idt-prod-gwc-domain`**. Set `name` to override. `domain_name` is a separate DNS value (the actual AD domain FQDN).

## Security posture (hardened by default)

Defaults follow Microsoft's [Harden a managed domain](https://learn.microsoft.com/entra/identity/domain-services/secure-your-domain): **Kerberos armoring ON**; **NTLM v1, TLS 1.0, Kerberos RC4 OFF**; **NTLM password sync OFF**; Kerberos password sync ON (required for auth). Override via `var.security`.

## Usage

```hcl
module "aadds" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/DomainServices?ref=v0.3.0"

  subscription_acronym = "idt"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "domain"

  location            = "germanywestcentral"
  resource_group_name = azurerm_resource_group.aadds.name

  domain_name       = "aadds.contoso.com"   # custom routable domain, NOT *.onmicrosoft.com
  sku               = "Standard"
  replica_subnet_id = module.network.subnet_ids["snet-aadds"]

  notifications = {
    additional_recipients = ["identity-ops@contoso.com"]
  }

  # optional LDAPS (sensitive)
  secure_ldap = {
    pfx_certificate          = filebase64("${path.module}/ldaps.pfx")
    pfx_certificate_password = var.ldaps_pfx_password
    external_access_enabled  = false
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}

# Point the VNet DNS at the managed domain controllers
# resource "azurerm_virtual_network_dns_servers" "aadds" {
#   virtual_network_id = module.network.vnet_id
#   dns_servers        = module.aadds.domain_controller_ip_addresses
# }
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/DomainServices"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  domain_name          = "aadds.contoso.com"
  replica_subnet_id    = dependency.network.outputs.subnet_ids["snet-aadds"]
  tags                 = include.root.inputs.common_tags
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | Explicit name override. Null = derived `aadds-…`. |
| `subscription_acronym` | `string` | `null` | Naming component (required unless `name` set). |
| `environment` | `string` | `null` | Environment (`prod`/`nprd`). |
| `region_code` | `string` | `null` | Region short code (e.g. `gwc`). |
| `workload` | `string` | `"domain"` | Naming suffix segment. |
| `location` | `string` | — (required) | Azure region. |
| `resource_group_name` | `string` | — (required) | RG hosting the managed domain. |
| `domain_name` | `string` | — (required) | AD domain FQDN. Leading label ≤ 15 chars (NetBIOS); use a custom routable domain, not `*.onmicrosoft.com`. ForceNew. |
| `replica_subnet_id` | `string` | — (required) | Subnet ARM ID for the initial replica set. ForceNew. |
| `sku` | `string` | `"Standard"` | `Standard` / `Enterprise` / `Premium`. |
| `domain_configuration_type` | `string` | `"FullySynced"` | `FullySynced` / `ResourceTrusting`. ForceNew. |
| `filtered_sync_enabled` | `bool` | `false` | Group-based scoped sync. |
| `notifications` | `object` | `{}` | `additional_recipients`, `notify_dc_admins` (true), `notify_global_admins` (true). |
| `security` | `object` | hardened | See *Security posture*. |
| `secure_ldap` | `object` (sensitive) | `null` | LDAPS: `pfx_certificate` (base64 PFX), `pfx_certificate_password`, `external_access_enabled` (false). |
| `lock` | `object({ kind, name })` | `null` | Optional CanNotDelete/ReadOnly lock (on top of `prevent_destroy`). |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Managed domain resource ID. |
| `name` | Managed domain resource name. |
| `domain_name` | DNS domain name. |
| `deployment_id` | Unique deployment ID. |
| `initial_replica_set_id` | Initial replica set ID. |
| `domain_controller_ip_addresses` | DC IPs of the initial replica set — point the VNet custom DNS at these. |
| `lock_ids` | Map of lock IDs (empty when `lock` is null). |

## Notes

- **`prevent_destroy = true`** on the resource — a managed domain holds directory state and password hashes; destruction is irreversible. Removing it requires a module fork.
- **ForceNew** fields: `domain_name`, `replica_subnet_id`, `domain_configuration_type` (and `name`, `location`, `resource_group_name`).
- **Provisioning is slow** — Azure takes ~1 hour to stand up the managed domain (provider create timeout is 3 h).

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: slug naming, hardened security defaults, optional LDAPS, optional lock, and validators (NetBIOS label length, FQDN, sku, subnet id). Run: `terraform init -backend=false && terraform test`.

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
| [azurerm_active_directory_domain_service.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/active_directory_domain_service) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| domain\_name | The DNS domain name for the managed domain (FQDN, e.g. aadds.contoso.com).<br><br>Constraints:<br>- Must be a valid FQDN with at least two labels.<br>- The leading label (used as the NetBIOS name) must be <= 15 characters.<br>- Use a **custom, routable** domain you own. Do NOT use the tenant default<br>  `*.onmicrosoft.com` — it is not routable and prevents secure LDAP with<br>  your own certificate (Microsoft owns that DNS namespace).<br>Changing this forces a new managed domain. | `string` | n/a | yes |
| location | Azure region where the managed domain is deployed. | `string` | n/a | yes |
| replica\_subnet\_id | Resource ID of the subnet for the initial replica set (dedicated /24+ subnet, NSG allowing AzureActiveDirectoryDomainServices). Changing this forces a new managed domain. | `string` | n/a | yes |
| resource\_group\_name | Resource group hosting the managed domain. | `string` | n/a | yes |
| domain\_configuration\_type | Configuration type. FullySynced (User Forest — syncs all objects) or ResourceTrusting (Resource Forest). Changing this forces a new managed domain. | `string` | `"FullySynced"` | no |
| environment | Environment (e.g. prod, nprd). | `string` | `null` | no |
| filtered\_sync\_enabled | Enable group-based filtered (scoped) synchronisation. | `bool` | `false` | no |
| lock | Optional Resource Lock. The resource also carries an unconditional<br>`lifecycle.prevent_destroy` guard at the Terraform level — this variable adds<br>a second, Azure-side guard that survives state loss/refresh.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit resource (display) name. If null, computed from naming components as aadds-{acronym}-{env}-{region}-{workload}. | `string` | `null` | no |
| notifications | Alert notifications for the managed domain (extra recipients + notify AAD DC Administrators / Global Administrators). | <pre>object({<br>    additional_recipients = optional(list(string), [])<br>    notify_dc_admins      = optional(bool, true)<br>    notify_global_admins  = optional(bool, true)<br>  })</pre> | `{}` | no |
| region\_code | Region code (e.g. gwc, weu). | `string` | `null` | no |
| secure\_ldap | Optional secure LDAP (LDAPS) configuration. Null = LDAPS disabled.<br>  - pfx\_certificate          : base64-encoded PKCS#12 (PFX) bundle holding the LDAPS cert + key.<br>  - pfx\_certificate\_password : password decrypting the PFX bundle.<br>  - external\_access\_enabled  : expose LDAPS (TCP 636) to the Internet. Default false —<br>                               keep OFF unless the subnet NSG restricts source ranges,<br>                               else you invite Internet bruteforce.<br>Marked sensitive: the whole object carries the certificate + password. | <pre>object({<br>    enabled                  = optional(bool, true)<br>    external_access_enabled  = optional(bool, false)<br>    pfx_certificate          = string<br>    pfx_certificate_password = string<br>  })</pre> | `null` | no |
| security | Managed domain security settings. Hardened by default per Microsoft's<br>"Harden a Microsoft Entra Domain Services managed domain":<br>  - Kerberos armoring ENABLED<br>  - NTLM v1, TLS 1.0, Kerberos RC4 DISABLED<br>  - NTLM password sync DISABLED<br>  - Kerberos password sync ENABLED (required for Kerberos authentication)<br>Set `sync_on_prem_passwords = true` only for hybrid tenants using Entra Connect.<br>Note: disabling `sync_ntlm_passwords` breaks LDAP simple binds — keep it off<br>unless a legacy app requires them. | <pre>object({<br>    kerberos_armoring_enabled       = optional(bool, true)  # ON  — FAST/Kerberos armoring<br>    kerberos_rc4_encryption_enabled = optional(bool, false) # OFF — weak cipher<br>    ntlm_v1_enabled                 = optional(bool, false) # OFF — legacy NTLM v1<br>    tls_v1_enabled                  = optional(bool, false) # OFF — legacy TLS 1.0<br>    sync_kerberos_passwords         = optional(bool, true)  # ON  — required for Kerberos auth<br>    sync_ntlm_passwords             = optional(bool, false) # OFF — do not sync NTLM hashes<br>    sync_on_prem_passwords          = optional(bool, false) # OFF — enable only for hybrid (Entra Connect)<br>  })</pre> | `{}` | no |
| sku | SKU for the managed domain. One of Standard, Enterprise, Premium. | `string` | `"Standard"` | no |
| subscription\_acronym | Subscription acronym (e.g. idt, con, mgm). | `string` | `null` | no |
| tags | Tags to apply to the managed domain. | `map(string)` | `{}` | no |
| workload | Workload name / naming suffix segment (e.g. domain). | `string` | `"domain"` | no |

## Outputs

| Name | Description |
|------|-------------|
| deployment\_id | Unique ID for the managed domain deployment. |
| domain\_controller\_ip\_addresses | Domain controller IP addresses of the initial replica set (typically two). Point the VNet's custom DNS servers at these. |
| domain\_name | The DNS domain name of the managed domain. |
| id | The ID of the managed domain. |
| initial\_replica\_set\_id | ID of the initial replica set. |
| lock\_ids | Map of management lock IDs (empty when var.lock is null). |
| name | The name of the managed domain resource. |
<!-- END_TF_DOCS -->
