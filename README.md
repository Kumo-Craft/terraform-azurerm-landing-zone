# Terraform Azure Landing Zone

Production-ready Azure landing zone authored as an **[AVM](https://azure.github.io/Azure-Verified-Modules/)-style monorepo** — a thin root module that bootstraps the foundational resource group, plus **62 submodules** under [`./modules/`](./modules/) covering the full CAF Enterprise Scale footprint (networking, compute, AVD, identity, security, monitoring, governance/policy, NVA).

Built for [Terragrunt](https://terragrunt.gruntwork.io/) isolation but usable standalone with any Terraform workflow.

## Quick start

The root module deploys a single resource group following the house naming convention. Everything else is a submodule consumed directly.

### From the HCP Terraform private registry (once published)

```hcl
# The root module — bootstraps a landing-zone RG
module "lz" {
  source  = "John6810/landing-zone/azurerm"
  version = "0.1.0"

  subscription_acronym = "shc"
  environment          = "nprd"
  region_code          = "gwc"
  location             = "germanywestcentral"
  workload             = "platform"
}

# Any submodule — e.g. a Key Vault
module "kv" {
  source  = "John6810/landing-zone/azurerm//modules/KeyVault"
  version = "0.1.0"
  # ...
}
```

### From GitHub (git source, pin to a tag)

```hcl
module "kv" {
  source = "git::https://github.com/Kumo-Craft/Modules.git//modules/KeyVault?ref=v0.1.0"
  # ...
}
```

See the live example: [`examples/basic-resource-group`](./examples/basic-resource-group/).

## Submodules

Browse `./modules/` for the full catalogue. Each submodule has its own README, `*.tf` files, and tests.

### Networking

| Submodule | Description |
|-----------|-------------|
| [Vnet](./modules/Vnet/) | Virtual Network with optional inline subnets, DDoS, and lock |
| [NetworkStack](./modules/NetworkStack/) | Regional spoke/hub bundle: RG + Network Watcher + VNet + subnets/NSGs/route tables (azapi) |
| [SubnetWithNsg](./modules/SubnetWithNsg/) | Subnet + NSG in a single API call (azapi, for Azure Policy compliance) |
| [NSG](./modules/NSG/) | Multiple Network Security Groups with validated rules |
| [RouteTable](./modules/RouteTable/) | Route Table with validated routes and lock |
| [VNetPeering](./modules/VNetPeering/) | VNet peerings (one direction per entry) |
| [NatGateway](./modules/NatGateway/) | NAT Gateway StandardV2 (zone-redundant, azapi) |
| [DnsResolver](./modules/DnsResolver/) | Private DNS Resolver with inbound/outbound endpoints and forwarding rules |
| [PrivateDnsZones](./modules/PrivateDnsZones/) | All Private Link (`privatelink.*`) DNS zones via AVM pattern module |
| [PrivateDnsZonesCorp](./modules/PrivateDnsZonesCorp/) | Corporate-internal Private DNS zones linked to VNets (companion to PrivateDnsZones) |
| [PrivateEndpoint](./modules/PrivateEndpoint/) | Private Endpoints for PaaS services with DNS zone groups |
| [NetworkWatcher](./modules/NetworkWatcher/) | Network Watcher with optional inline Resource Group |
| [FlowLogs](./modules/FlowLogs/) | VNet Flow Logs + optional Traffic Analytics (modern VNet-targeted API) |
| [DdosProtection](./modules/DdosProtection/) | DDoS Protection Plan |
| [ExpressRouteCircuit](./modules/ExpressRouteCircuit/) | ExpressRoute Circuit with optional Private + Microsoft peering |

### Compute & Containers

| Submodule | Description |
|-----------|-------------|
| [Aks](./modules/Aks/) | Private AKS cluster (CNI Overlay, KMS v2, OIDC/WI, Defender, Prometheus) |
| [AksStack](./modules/AksStack/) | RG + AKS + supporting resources composed in a single deploy |
| [KubernetesClusterExtension](./modules/KubernetesClusterExtension/) | ARM-managed AKS cluster extension (Microsoft.KubernetesConfiguration) |
| [ArgoCDBootstrap](./modules/ArgoCDBootstrap/) | Argo CD repo connection + root Application CRD (assumes Argo CD already installed) |
| [ContainerRegistry](./modules/ContainerRegistry/) | ACR Premium with zone redundancy, RBAC, and lock |
| [ApplicationGateway](./modules/ApplicationGateway/) | Application Gateway WAF v2 with DRS 2.1 managed rules |
| [Vm-Windows](./modules/Vm-Windows/) | Windows VM (NIC, Entra login, MSI, optional CMK disks + data disks) |
| [ComputeGallery](./modules/ComputeGallery/) | Compute Gallery (Shared Image Gallery) + optional Trusted-Launch image definition |

### Azure Virtual Desktop (AVD)

| Submodule | Description |
|-----------|-------------|
| [AvdHostPool](./modules/AvdHostPool/) | AVD Host Pool (Pooled/Personal) with auto-rotating registration token |
| [AvdSessionHost](./modules/AvdSessionHost/) | Windows session-host VMs (Entra Join → AVD DSC → FSLogix) |
| [AvdApplicationGroup](./modules/AvdApplicationGroup/) | AVD Application Group (Desktop or RemoteApp) bound to a host pool |
| [AvdWorkspace](./modules/AvdWorkspace/) | AVD Workspace aggregating application groups for the client |
| [AvdScalingPlan](./modules/AvdScalingPlan/) | AVD Autoscale plan (schedule-based start/stop/drain) |
| [AvdImageTemplate](./modules/AvdImageTemplate/) | Azure Image Builder template (azapi): marketplace base → scripts → Compute Gallery version |
| [AvdStack](./modules/AvdStack/) | Composite: HostPool + Application Groups + Workspace (+ Scaling Plan, + Session Hosts) wired end-to-end |

### Security & Identity

| Submodule | Description |
|-----------|-------------|
| [KeyVault](./modules/KeyVault/) | Key Vault with RBAC, network ACLs, lock, and role assignments |
| [KeyVault-Key](./modules/KeyVault-Key/) | Key Vault keys (RSA/EC) with rotation policies |
| [KeyVault-Secrets](./modules/KeyVault-Secrets/) | Push secrets (caller-provided or auto-generated) to an existing Key Vault |
| [KeyVaultStack](./modules/KeyVaultStack/) | RG + Key Vault + Private Endpoint (single deploy) |
| [TlsSelfSignedCert](./modules/TlsSelfSignedCert/) | Self-signed TLS cert imported into a Key Vault (internal/non-prod) |
| [ManagedIdentity](./modules/ManagedIdentity/) | User-Assigned Managed Identity with federated credentials and RBAC |
| [RbacAssignments](./modules/RbacAssignments/) | Bulk RBAC assignments for Entra ID groups and managed identities |
| [RoleAssignment](./modules/RoleAssignment/) | Thin single-grant `azurerm_role_assignment` wrapper (cross-scope, no azuread dep) |

### Network Security (NVA)

| Submodule | Description |
|-----------|-------------|
| [PaloCluster](./modules/PaloCluster/) | Palo Alto VM-Series HA cluster (ILB, CMK encryption, App Insights) |
| [vwan](./modules/vwan/) | Virtual WAN + Hubs + VPN Sites + S2S connections |

### Monitoring & Observability

| Submodule | Description |
|-----------|-------------|
| [AzureMonitorWorkspace](./modules/AzureMonitorWorkspace/) | Azure Monitor Workspace (Managed Prometheus) with optional PE |
| [PrometheusCollector](./modules/PrometheusCollector/) | DCR + recording rules for AKS Prometheus metrics |
| [PrometheusAlertRules](./modules/PrometheusAlertRules/) | AMBA-style Managed Prometheus alert rule groups for AKS |
| [ContainerInsightsCollector](./modules/ContainerInsightsCollector/) | Explicit DCR/DCRA for Container Insights → LAW (oms_agent override) |
| [LogAnalyticsAlerts](./modules/LogAnalyticsAlerts/) | KQL scheduled-query alerts + optional Logs Ingestion API pipeline |
| [Grafana](./modules/Grafana/) | Azure Managed Grafana with identity, AMW integration, and Entra RBAC |
| [ActionGroup](./modules/ActionGroup/) | Monitor Action Group (email + push receivers) |
| [DiagnosticSettings](./modules/DiagnosticSettings/) | Diagnostic Settings to LAW, Storage, Event Hub, or partner |
| [Ampls](./modules/Ampls/) | Azure Monitor Private Link Scope with scoped services and PE |
| [SecurityCenterWorkspace](./modules/SecurityCenterWorkspace/) | Redirect Defender for Cloud telemetry to a central LAW |
| [FinOpsHub](./modules/FinOpsHub/) | FinOps Hub (Cost Management with ADX + ADF) |

### Governance & Policy

| Submodule | Description |
|-----------|-------------|
| [AlzArchitecture](./modules/AlzArchitecture/) | ALZ Management Group hierarchy, policies, and Defender |
| [AlzManagement](./modules/AlzManagement/) | ALZ Management resources (LAW, Automation Account) |
| [PolicyDefinition](./modules/PolicyDefinition/) | Custom Policy Definitions (sub- or MG-scoped), upstream anchor of the Policy* family |
| [PolicySetDefinition](./modules/PolicySetDefinition/) | Policy Set Definitions (initiatives) — sub- or MG-scoped |
| [PolicyAssignment](./modules/PolicyAssignment/) | Policy assignments (MG/Sub/RG) with optional MSI + inline DINE/Modify role grants |
| [PolicyExemption](./modules/PolicyExemption/) | Policy exemptions (MG/Sub/RG) — canonical 3-scope dispatch pattern |
| [PolicyRemediation](./modules/PolicyRemediation/) | Policy remediation tasks (MG/Sub/RG/Resource) for DINE/Modify effects |

### Platform / Foundation

| Submodule | Description |
|-----------|-------------|
| [Naming](./modules/Naming/) | House naming convention wrapper (uses `Azure/naming/azurerm`) |
| [ResourceGroup](./modules/ResourceGroup/) | Resource Groups (map-shape, 1..N per apply) with optional lock + role assignments |
| [ResourceLock](./modules/ResourceLock/) | Management locks (CanNotDelete / ReadOnly) on any scope |
| [StorageAccount](./modules/StorageAccount/) | Storage Account with containers, RBAC, and lock |

## Examples

| Example | Description |
|---------|-------------|
| [basic-resource-group](./examples/basic-resource-group/) | Minimal usage of the root module: deploys a single landing-zone resource group |
| [secure-spoke](./examples/secure-spoke/) | Full secure-by-default spoke: root RG + NetworkStack + KeyVault + StorageAccount, all consumed via Private Endpoints |

## Module Patterns

All submodules follow consistent patterns aligned with [AVM specifications](https://azure.github.io/Azure-Verified-Modules/):

### Naming Convention

```
{resource-prefix}-{subscription_acronym}-{environment}-{region_code}-{workload}
```

Example: `aks-api-prod-gwc-001`, `kv-mgm-prod-gwc-secrets`, `crapiprodgwc001` (ACR, no hyphens).

Name composition is centralized in the [`Naming`](./modules/Naming/) submodule, which wraps [`Azure/naming/azurerm`](https://registry.terraform.io/modules/Azure/naming/azurerm/0.4.3). Every submodule accepts an optional `name` variable to override the computed name.

### Common Interfaces

| Interface | Pattern | Description |
|-----------|---------|-------------|
| **Collections** | `map(object)` | All iterable inputs use maps with arbitrary keys (safe at plan-time) |
| **Role assignments** | `role_definition_id_or_name` | Unified field with `strcontains()` auto-detection of ID vs name |
| **Locks** | `var.lock { kind, name }` | Optional management lock (CanNotDelete / ReadOnly). Each submodule accepts the same shape and delegates to the canonical [`ResourceLock`](./modules/ResourceLock/) submodule via a relative source (`../ResourceLock`) — single source of truth, no inline `azurerm_management_lock`. |
| **Required vars** | `nullable = false` | All required variables enforce non-null at plan-time |
| **Validations** | regex + contains | Naming vars, resource IDs, enum values validated at plan-time |
| **Outputs** | `output "resource"` | Every submodule exposes the complete primary resource object |
| **Tags** | `CreatedOn` auto-tag | Immutable creation timestamp via `time_static` |

### Security Defaults

| Default | Value | Submodules |
|---------|-------|------------|
| Public network access | `false` | KeyVault, StorageAccount, ACR, AKS, Grafana, AMW |
| TLS version | `1.2` | StorageAccount |
| RBAC authorization | `true` | KeyVault, KeyVaultStack |
| Purge protection | `true` | KeyVault, KeyVaultStack, PaloCluster KV |
| Shared access keys | `false` | StorageAccount |
| `prevent_destroy` | `true` | KeyVault, KeyVaultStack, ACR, DDoS, StorageAccount, AKS, PaloCluster VMs/KV/Key/DES |
| PE lifecycle ignore | `[private_dns_zone_group]` | All submodules with Private Endpoints (ALZ DINE policy compat) |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| azapi | ~> 2.x (SubnetWithNsg, NatGateway, NetworkStack) |
| azuread | ~> 3.0 (RbacAssignments) |
| tls | ~> 4.0 (TlsSelfSignedCert) |
| kubernetes | ~> 3.0 (ArgoCDBootstrap) |
| time | >= 0.9.0 |
| random | >= 3.3.2 (transitively via `Naming`) |

## Versioning & Releases

This monorepo uses **single global SemVer tags** for the whole module family (root + all submodules):

```
v<MAJOR>.<MINOR>.<PATCH>
```

Examples: `v0.1.0`, `v0.2.0`, `v1.0.0`. One tag = one coordinated release of the root + every submodule. Consumers pin to a single version and get a consistent set.

### Bump rules

| Change | Bump |
|--------|------|
| Add an optional variable / new output / new submodule | **MINOR** |
| Add a required variable, rename / remove an existing variable or output, change a default in a way that triggers replace, restructure a submodule | **MAJOR** |
| Bug fix with no surface change | **PATCH** |
| `azurerm` provider major bump | **MAJOR** (forces consumer plan review) |

Releases in the `v0.x.y` series are pre-1.0 — minor versions MAY include breaking changes.

### How a release is cut

1. Merge changes to `main` (`terraform validate`/`fmt` clean on root + touched submodules, tests green).
2. Tag the commit: `git tag v<X.Y.Z> && git push origin v<X.Y.Z>`.
3. Pushing the tag triggers the [`Release`](.github/workflows/release.yml) GitHub Actions workflow, which builds the terraform-docs bundle + auto-generated release notes (git log since the previous tag) and publishes them as a GitHub Release.
4. If the repo is connected to an HCP Terraform private registry, the tag is auto-imported as a new version.

### Legacy per-module tags

Two per-module tags exist from the pre-AVM-restructure period:
- `Naming/v0.1.0`
- `ResourceGroup/v1.0.0`

They pin to the pre-restructure layout (modules at root, not under `modules/`). Existing consumers using them keep working — but new consumers should pin to `v0.1.0` or later.

## License

This project is licensed under the MPL-2.0 License — see the [LICENSE](LICENSE) file for details.
