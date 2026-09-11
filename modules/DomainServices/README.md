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
