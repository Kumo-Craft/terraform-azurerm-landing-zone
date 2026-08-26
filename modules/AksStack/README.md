# AksStack

## Breaking changes (v0.2.66)

### Inline resource group removed — caller now provides `var.resource_group_name` (F-6)

AksStack no longer creates or looks up the resource group. The `create_resource_group`
and `resource_group_workload` variables are removed. Callers must pass
`resource_group_name` pointing at a pre-existing RG (typically created by the
`ResourceGroup` module upstream).

**Migration recipe**:

1. Remove `create_resource_group` and `resource_group_workload` from your inputs.
2. Ensure `resource_group_name` is set to the existing RG name (if you previously
   used `create_resource_group = false`, this value is unchanged).
3. If you previously used `create_resource_group = true` (the old default), run:
   ```
   terraform state rm 'module.aks_stack.module.rg[0]'
   ```
   This removes the `ResourceGroup` child module from Terraform state while leaving
   the RG itself intact in Azure. After this, manage the RG with a separate
   `ResourceGroup` module or manually, and pass its name as `resource_group_name`.

### `user_node_pools[*].enable_auto_scaling` renamed to `auto_scaling_enabled` (F-18 pass-through)

Aligns with the Aks v0.2.65 BREAKING rename which matches the azurerm 4.x provider
schema field name. No state migration required (variable shape only).

**Before**:
```hcl
user_node_pools = {
  user = {
    name                = "user"
    vm_size             = "Standard_D4ds_v5"
    enable_auto_scaling = true
  }
}
```

**After**:
```hcl
user_node_pools = {
  user = {
    name                 = "user"
    vm_size              = "Standard_D4ds_v5"
    auto_scaling_enabled = true
  }
}
```

---

## Breaking changes (v0.2.51)

### `system_pool_only_critical_addons_enabled` default flipped `false` → `true` (F-5)

The default for `system_pool_only_critical_addons_enabled` changed from `false`
to `true` to align with Aks v0.2.50 secure-by-default and the Microsoft AKS
best practice of keeping workload pods off the system node pool
(CriticalAddonsOnly=true:NoSchedule taint).

**Who is affected**: callers that rely on the `false` default — i.e., clusters
that have no user node pool OR that run workloads (e.g. Rancher Fleet agents)
without a `CriticalAddonsOnly` toleration.

**Migration recipe**: before upgrading to v0.2.51, add the following to your
stack configuration if you fall into either category:

```hcl
system_pool_only_critical_addons_enabled = false
```

If you do not set this before the next apply, Terraform will apply the
CriticalAddonsOnly taint to the system node pool. Kubernetes will then
re-schedule any workload pods that lack the matching toleration away from the
system node pool. In a single-pool cluster this means those pods become
unschedulable until a user node pool is added or the flag is reverted.

---

Full AKS workload bundle in **one Terragrunt apply** — replaces 7 separate
deployments (`rg-aks`, `id-aks-cp`, `id-aks-kubelet`, `kv-{wl}`, `kv-key-etcd`,
`aks-*`, `rbac-*`) with a single composed module.

> **Composition strategy: wrapper (B2)** — AksStack does **not** inline
> resources. It calls the canonical child modules (`ManagedIdentity`,
> `KeyVault`, `KeyVault-Key`, `PrivateEndpoint`, `Aks`) via relative paths
> (`../Sibling`), so any fix to the child modules propagates here at the
> next release bump.

## What it builds

| Resource | Count | Notes |
|---|---|---|
| Resource Group | 0–1 | Optional via `create_resource_group` |
| User Assigned Identity (Control Plane) | 1 | `id-{prefix}-aks-cp` |
| User Assigned Identity (Kubelet) | 1 | `id-{prefix}-aks-kubelet` |
| Key Vault (Premium, RBAC, public access disabled) | 1 | `kv-{prefix}-{kv_workload}{kv_suffix}` |
| Key Vault Private Endpoint | 1 | Subresource `vault`, on `kv_pe_subnet_id` |
| Key Vault Key (etcd CMK, RSA-2048, rotated) | 1 | `aks-etcd-key` |
| AKS Cluster | 1 | Private + Azure CNI Overlay + AAD RBAC + WI |
| User Node Pools | 0–N | via `var.user_node_pools` map |
| Diagnostic Setting | 0–1 | Created by the wrapped Aks module when `log_analytics_workspace_id` is set |
| Role Assignments | 5–N | KV admin setup + KV Crypto User (kubelet KMS) + Network Contributor on node/apiserver subnets + MI Operator (kubelet) + KV Contributor (CP, gated on `kms_v2_enabled`) + ACR Pull (kubelet) + cluster admins/users (optional) |

## Built-in Microsoft AKS best practices

- **Private cluster** (`private_cluster_enabled = true`)
- **Azure CNI Overlay** (efficient pod IP usage); optional **Cilium dataplane** via `network_data_plane = "cilium"` + `network_policy = "cilium"`
- **API Server VNet Integration** + **KMS v2 Private etcd encryption** auto-bootstrapped via `azapi_update_resource` (PATCH after cluster create — no manual `az aks update` needed)
- **OIDC issuer + Workload Identity** (federated credentials for AAD-aware pods)
- **AAD RBAC + Azure RBAC for Kubernetes** (no local accounts)
- **Microsoft Defender for Containers** (when `log_analytics_workspace_id` is set)
- **Managed Prometheus** (`monitor_metrics {}` + `ama-metrics-*` DaemonSet)
- **Azure Policy add-on** (Gatekeeper)
- **Image Cleaner** (48h interval default)
- **Auto-upgrade stable** (cluster) + **Node OS SecurityPatch** (nodes)
- **Encryption at host** (system pool default-on; user pools opt-in via map)
- **Maintenance window** (configurable)
- **Multi-zone** (`["1", "2", "3"]`) for AZ redundancy

> **Container Insights** is **NOT** enabled by AksStack — it's delegated to
> the **ALZ DINE Policy** (`Deploy-AKS-DefenderForCloud-Addon`). The wrapped
> Aks module includes `oms_agent` in `lifecycle.ignore_changes` to prevent
> Terraform from fighting the Policy. If your environment doesn't run ALZ
> Policy, deploy `azurerm_monitor_diagnostic_setting` for `Microsoft.OperationalInsights/workspaces` separately.

## Bootstrap (automatic)

When `api_server_subnet_id` is set, the wrapped Aks module runs 3 post-create
steps in sequence — all inside the same `terragrunt apply`:

1. **VNet integration** — `azapi_update_resource.enable_vnet_integration` (PATCH `apiServerAccessProfile`)
2. **Cluster restart** — `null_resource.restart_after_vnet_integration` (`az aks stop && az aks start`, ~15min, [required by Microsoft](https://learn.microsoft.com/en-us/azure/aks/api-server-vnet-integration))
3. **KMS Private** — `azapi_update_resource.enable_kms` (PATCH `securityProfile.azureKeyVaultKms`)

Idempotent — re-apply = no-op if already configured.

The cluster restart `null_resource` requires `ARM_CLIENT_ID/SECRET/TENANT_ID`
env vars on the runner (CLI fallback only). The 2 azapi PATCHes work with any
Terraform auth (incl. WIF/OIDC).

`output.post_deploy_az_cli_commands` exposes the same `az aks update` commands
as a **fallback runbook** — for disaster recovery if Terraform state ever
drifts. Not part of the standard deployment flow.

The cluster's `lifecycle.ignore_changes = [api_server_access_profile, key_management_service]`
prevents azurerm from reverting what azapi has set on subsequent applies.

## Network primitives are external

`AksStack` does **not** create VNets, subnets, NSGs or route tables. Provision
those via [`NetworkStack`](../NetworkStack/) and pass:

- `node_subnet_id` — subnet for the node pools
- `api_server_subnet_id` — optional, for API Server VNet Integration (delegation `Microsoft.ContainerService/managedClusters` required)
- `kv_pe_subnet_id` — **required**, subnet for the Key Vault Private Endpoint

## Usage — Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/AksStack"
}

dependency "rg" {
  config_path = "../resource-group"   # ResourceGroup output
}

dependency "network" {
  config_path = "../network"          # NetworkStack output
}

dependency "alz_management" {
  config_path = "${get_repo_root()}/landing-zone/platform/management/alz-management"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "001"
  location             = include.root.inputs.location
  tenant_id            = include.root.locals.tenant_id

  # ── Resource Groups (existing — created by ResourceGroup) ──────────
  create_resource_group  = false
  resource_group_name    = dependency.rg.outputs.names["aks"]
  kv_resource_group_name = dependency.rg.outputs.names["kv"]   # optional separation of duties

  # ── Network (from NetworkStack) ─────────────────────────────────────
  node_subnet_id       = dependency.network.outputs.subnet_ids["aks"]
  api_server_subnet_id = dependency.network.outputs.subnet_ids["apiserver"]   # null = no VNet integration
  kv_pe_subnet_id      = dependency.network.outputs.subnet_ids["pe"]          # required

  # ── KMS v2 toggle ─────────────────────────────────────────────────
  # true  : auto-bootstrap KMS Private (azapi PATCH after cluster create)
  # false : etcd CMK created in KV but not wired into AKS
  kms_v2_enabled = true

  # ── KV admins (in addition to the deployer SP, which gets KV Admin
  #               via assign_rbac_to_current_user) ──────────────────
  kv_admin_principal_ids = [
    "<entra-group-objectId-for-kv-admin>",
  ]

  # ── Cluster sizing ─────────────────────────────────────────────────
  system_pool_vm_size      = "Standard_D4ds_v5"
  system_pool_auto_scaling = true
  system_pool_min_count    = 3   # 1 per AZ
  system_pool_max_count    = 5

  user_node_pools = {
    user = {
      name                = "user"
      vm_size             = "Standard_D4ds_v5"
      min_count           = 3
      max_count           = 6
      auto_scaling_enabled = true
      labels              = { workload = "apps" }
      # Spot pool: priority = "Spot", eviction_policy = "Delete"
    }
  }

  # ── Maintenance (Sat 02-06 CET) ────────────────────────────────────
  maintenance_window = {
    day        = "Saturday"
    hour_start = 1   # UTC = CET - 1
    hour_end   = 5
  }

  # ── Cross-sub LAW for diagnostic settings + Defender ─────────────
  log_analytics_workspace_id = dependency.alz_management.outputs.law_id

  # ── ACR pull (kubelet → AcrPull on each ACR) ──────────────────────
  acr_pull_target_ids = []

  # ── Cluster RBAC (env-aware caller-side) ───────────────────────────
  cluster_admin_principal_ids = ["<entra-group-objectId-for-aks-admin>"]
  cluster_user_principal_ids  = ["<entra-group-objectId-for-aks-user>"]
}
```

## Notable variables (not in the example above)

| Variable | Default | Purpose |
| --- | --- | --- |
| `kv_pe_dns_propagation_wait` | `5m` | Sleep after KV PE before AKS create — gives ALZ DINE time to deploy the privateDnsZoneGroup. Set `0s` to skip. |
| `network_data_plane` | `azure` | Set to `cilium` (eBPF) — requires `network_policy = "cilium"`. NPM EOL 2028-09-30, prefer Cilium for new clusters. |
| `private_cluster_public_fqdn_enabled` | auto | Computed from `private_dns_zone_id`. Set `false` in prod to hide cluster existence even from DNS. |
| `kv_suffix` | `null` | Appended to KV name (e.g. to dodge soft-delete name conflicts). |
| `kms_v2_enabled` | `false` | Gates the KMS Private wiring. Etcd CMK is always created. |
| `acr_pull_target_ids` | `[]` | List of ACR resource IDs — kubelet UAMI gets `AcrPull` on each. |

## Trade-offs vs. 7 separate deployments

| Pro | Contre |
|---|---|
| 1 deployment instead of 7 | Bigger blast radius (1 apply = full cluster + KV + IDs + RBAC) |
| Cross-resource invariants validated at plan time | State file size 7× larger |
| Onboarding new AKS workload = 1 file, ~50 lines | Selective destroy harder (need `state rm` to drop one piece) |
| Fewer dep-chain races at apply | Pre-existing 7-deployment setups need state migration to adopt |

For existing apimanager-style deployments, **don't migrate** — the
7-deployment pattern works. Use AksStack for **new AKS workloads**.

## Outputs

See [`output.tf`](output.tf). Key ones for downstream callers:

| Output | Use |
| --- | --- |
| `cluster_id` / `cluster_name` / `cluster_fqdn` | AKS cluster resource references |
| `node_resource_group_name` | The MC_* RG where VMSS / NICs / LBs live |
| `oidc_issuer_url` | Workload Identity federated credential issuer |
| `kubelet_identity` / `control_plane_identity` | Full UAMI objects (id, principal_id, client_id) |
| `key_vault_id` / `key_vault_name` / `key_vault_uri` | Key Vault references for additional role assignments / secrets |
| `etcd_key_id` / `etcd_key_versionless_id` | KMS key URIs |
| `kv_private_endpoint_id` / `kv_private_endpoint_ip` | KV PE references for DNS / firewall debugging |
| `kv_resource_group_name` / `resource_group_id` | RG references when KV uses a separate RG |
| `post_deploy_az_cli_commands` | **Fallback runbook only** — bootstrap is automatic, this output exists for state-drift recovery |

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
| aks | ../Aks | n/a |
| cluster\_admin | ../RoleAssignment | n/a |
| cluster\_user | ../RoleAssignment | n/a |
| cp\_apiserver\_subnet\_network\_contrib | ../RoleAssignment | n/a |
| cp\_kubelet\_mi\_operator | ../RoleAssignment | n/a |
| cp\_kv\_contributor | ../RoleAssignment | n/a |
| cp\_kv\_crypto\_user | ../RoleAssignment | n/a |
| cp\_subnet\_network\_contrib | ../RoleAssignment | n/a |
| etcd\_key | ../KeyVault-Key | n/a |
| id\_cp | ../ManagedIdentity | n/a |
| id\_kubelet | ../ManagedIdentity | n/a |
| kubelet\_acr\_pull | ../RoleAssignment | n/a |
| kubelet\_kv\_crypto\_user | ../RoleAssignment | n/a |
| kv | ../KeyVault | n/a |
| kv\_pe | ../PrivateEndpoint | n/a |

## Resources

| Name | Type |
|------|------|
| [time_sleep.wait_for_dine_dns](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | n/a | `string` | n/a | yes |
| kv\_pe\_subnet\_id | Subnet ID where the Private Endpoint targeting the etcd CMK Key Vault is<br>deployed. The PE exposes subresource 'vault'. The privateDnsZoneGroup is<br>created automatically by ALZ DINE Policy (cross-sub privatelink.vaultcore.azure.net<br>zone in connectivity), so this stack does not pass private\_dns\_zone\_ids.<br><br>Mandatory: every KV in this LZ must have a PE — KV is deployed with<br>public\_network\_access\_enabled = false and the AKS control plane (or any<br>caller) needs the PE to reach the etcd CMK for KMS v2. | `string` | n/a | yes |
| location | ############################################################## REQUIRED ############################################################## | `string` | n/a | yes |
| node\_subnet\_id | Subnet ID for AKS nodes (must be a /24 minimum, no NSG-required policy violation since you should provision via SubnetWithNsg or NetworkStack). | `string` | n/a | yes |
| region\_code | n/a | `string` | n/a | yes |
| resource\_group\_name | Name of the pre-existing resource group for the AKS cluster and UAMIs. Caller-managed (AksStack no longer creates the RG). | `string` | n/a | yes |
| subscription\_acronym | ############################################################## NAMING ############################################################## | `string` | n/a | yes |
| tenant\_id | Azure AD tenant ID for AAD RBAC + KV | `string` | n/a | yes |
| acr\_pull\_target\_ids | Container Registry resource IDs where the kubelet UAMI should get AcrPull (image pull). Empty = no ACR wired. | `list(string)` | `[]` | no |
| api\_server\_subnet\_id | Optional subnet ID for API Server VNet Integration. When set, KMS v2 + VNet integration must be enabled out-of-band via 'az aks update' (azurerm v4 limitation). Set to null to keep API Server fully managed. | `string` | `null` | no |
| automatic\_upgrade\_channel | n/a | `string` | `"stable"` | no |
| availability\_zones | ############################################################## SYSTEM NODE POOL ############################################################## | `list(string)` | <pre>[<br>  "1",<br>  "2",<br>  "3"<br>]</pre> | no |
| cluster\_admin\_principal\_ids | Object IDs granted Azure Kubernetes Service RBAC Cluster Admin on this cluster (PIM-eligible group in prod, RBAC permanent in nprd). | `list(string)` | `[]` | no |
| cluster\_user\_principal\_ids | Object IDs granted Azure Kubernetes Service Cluster User Role (kubectl exec/logs scope, no admin). | `list(string)` | `[]` | no |
| cost\_analysis\_enabled | Enable AKS Cost Analysis (namespace-level cost breakdown in the Azure<br>Portal). Free, opt-in. Requires sku\_tier in ("Standard", "Premium") —<br>rejected when sku\_tier = "Free". | `bool` | `false` | no |
| dns\_service\_ip | n/a | `string` | `"172.16.0.10"` | no |
| enable\_container\_insights | Enable Container Insights via the oms\_agent addon (modern MSI-auth<br>variant, msi\_auth\_for\_monitoring\_enabled = true). Installs the<br>ama-logs DaemonSet on every node; AKS auto-creates a default DCR/DCRA<br>tied to var.log\_analytics\_workspace\_id.<br><br>Pattern aligned with MS Learn Terraform docs<br>(https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable).<br><br>Callers typically deploy a separate ContainerInsightsCollector module<br>in addition to this addon — that module installs an explicit DCR with<br>custom streams (ContainerLogV2 only, skip Perf, etc.). | `bool` | `true` | no |
| enable\_secrets\_store\_csi\_driver | Enable the Secrets Store CSI Driver addon (azure-keyvault-secrets-provider).<br>Pattern aligned with MS Learn Terraform docs<br>(https://learn.microsoft.com/azure/aks/csi-secrets-store-driver, updated<br>2026-05-05).<br><br>AKS auto-creates a UAMI in the node RG (`azurekeyvaultsecretsprovider-*`)<br>— cannot opt out. RBAC on Key Vault NOT granted by AksStack; apps are<br>expected to use Workload Identity per-pod (the cluster already has<br>oidc\_issuer + workload\_identity enabled). | `bool` | `false` | no |
| enable\_web\_app\_routing | Enable the AKS Application Routing addon (managed nginx ingress).<br>Modern AKS-native ingress; supports both internal (private LB) and<br>external (Internet) via web\_app\_routing\_default\_nginx\_controller or<br>per-Ingress annotation. | `bool` | `false` | no |
| etcd\_key\_rotation\_policy | Rotation policy on the etcd CMK. Default: rotate after 1 year, expire after 2 years, notify 30d before expiry. | <pre>object({<br>    expire_after         = optional(string, "P2Y")<br>    notify_before_expiry = optional(string, "P30D")<br>    automatic = optional(object({<br>      time_after_creation = optional(string, "P1Y")<br>      time_before_expiry  = optional(string)<br>    }), { time_after_creation = "P1Y" })<br>  })</pre> | `{}` | no |
| image\_cleaner\_enabled | n/a | `bool` | `true` | no |
| image\_cleaner\_interval\_hours | n/a | `number` | `48` | no |
| keda\_enabled | n/a | `bool` | `false` | no |
| kms\_v2\_enabled | Whether to wire the etcd CMK into the AKS cluster. Default false because:<br><br>- When true AND api\_server\_subnet\_id is null: the Aks module creates an<br>  inline `key_management_service` block with `key_vault_network_access =<br>  "Private"`. The cluster control plane MUST reach the KV via private<br>  networking — typically a PE on the KV in the workload sub. Without that<br>  PE, the apply fails at AKS create time.<br>- When true AND api\_server\_subnet\_id is set: the inline block stays empty<br>  (Aks module gate), KMS must be enabled out-of-band via `az aks update`<br>  post-deploy (azurerm v4 limitation).<br>- When false: the etcd CMK is still created (cheap, forward-compatible),<br>  but AKS is deployed without KMS v2. Enable later via `az aks update`<br>  once the KV PE / VNet integration is in place.<br><br>Recommendation: deploy with kms\_v2\_enabled = false on greenfield workloads,<br>add the KV PE separately, then flip to true (or run the post-deploy CLI). | `bool` | `false` | no |
| kubernetes\_version | Kubernetes minor version (e.g. '1.34'). null = AKS default. | `string` | `null` | no |
| kv\_admin\_principal\_ids | Object IDs of principals (admins, deployer SP, AAD groups) granted Key Vault Administrator at the KV scope. Required at least to create the etcd CMK. Empty list = only the kubelet UAMI (Crypto User) gets access. | `list(string)` | `[]` | no |
| kv\_pe\_dns\_propagation\_wait | Sleep duration after KV Private Endpoint creation, before the AKS cluster<br>is created. Gives ALZ DINE Policy time to deploy the privateDnsZoneGroup<br>(cross-sub privatelink.vaultcore.azure.net A record) so the AKS control<br>plane can resolve the KV via private IP at KMS-attach time.<br><br>Format: Go duration string ('30s', '3m', '5m'). Set '0s' to disable.<br>Default '5m' covers DINE latency in most tenants. Increase if you observe<br>KMS-unreachable errors at first apply.<br><br>Only sleeps on initial PE creation — subsequent applies are unaffected. | `string` | `"5m"` | no |
| kv\_resource\_group\_name | Optional separate resource group for the etcd CMK Key Vault, its Private<br>Endpoint and the etcd KV Key. Default null = same RG as the cluster.<br><br>Recommended in production: a dedicated RG with a CanNotDelete lock isolates<br>the cryptographic material from the compute lifecycle. Loss of the etcd CMK<br>KV permanently breaks the cluster (KMS v2 cannot decrypt etcd state), so<br>separating its lifecycle from the (more frequently destroyed) compute RG<br>is sound separation of duties + extra safeguard. | `string` | `null` | no |
| kv\_sku\_name | Key Vault SKU. 'premium' is required for HSM-backed keys (recommended for etcd CMK). | `string` | `"premium"` | no |
| kv\_soft\_delete\_retention\_days | n/a | `number` | `90` | no |
| kv\_suffix | Optional suffix appended to the computed KV name (e.g. '002'). KV total name must stay ≤ 24 chars. | `string` | `null` | no |
| kv\_workload | Workload segment in the KV name (kv-{prefix}-{kv\_workload}). Default 'kv'. | `string` | `"kv"` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the AKS cluster (propagated to ../Aks). Production clusters should use CanNotDelete. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| log\_analytics\_workspace\_id | Cross-sub Platform LAW resource ID — used by Microsoft Defender + AKS diagnostic settings. null = skip both (not recommended in production). | `string` | `null` | no |
| maintenance\_window | AKS upgrade maintenance window. day = day-of-week, hour\_start/end in UTC. | <pre>object({<br>    day        = string<br>    hour_start = number<br>    hour_end   = number<br>  })</pre> | `null` | no |
| network\_data\_plane | Dataplane for Azure CNI Overlay: 'azure' (default) or 'cilium' (eBPF-based,<br>enables Advanced Container Networking Services). Cilium dataplane requires<br>network\_policy = 'cilium'. Greenfield clusters can opt in for better<br>performance + observability; brownfield clusters cannot switch dataplane<br>in place. | `string` | `"azure"` | no |
| network\_policy | n/a | `string` | `"azure"` | no |
| node\_os\_upgrade\_channel | n/a | `string` | `"SecurityPatch"` | no |
| node\_resource\_group\_name | AKS node resource group name (managed by AKS). Default 'rg-{prefix}-aks-nodes'. | `string` | `null` | no |
| outbound\_type | userDefinedRouting forces traffic via the spoke RT (default route → NVA). loadBalancer creates an AKS-managed PIP. | `string` | `"userDefinedRouting"` | no |
| pod\_cidr | ############################################################## NETWORK PROFILE — Azure CNI Overlay (Microsoft default) ############################################################## | `string` | `"10.244.0.0/16"` | no |
| private\_cluster\_public\_fqdn\_enabled | Whether AKS publishes a public FQDN that resolves to the private API<br>server IP. null = auto-derive from private\_dns\_zone\_id ('None' -> true,<br>custom zone -> false). Set explicitly to false in production to hide<br>the cluster's existence from public DNS queries. | `bool` | `null` | no |
| private\_dns\_zone\_id | Private DNS zone for the AKS API server. 'None' = AKS-managed (recommended for ALZ DINE). | `string` | `"None"` | no |
| secrets\_store\_csi\_driver\_rotation\_enabled | Enable Secrets Store CSI Driver auto-rotation. Default true (MS recommended). | `bool` | `true` | no |
| secrets\_store\_csi\_driver\_rotation\_interval | Secret rotation polling interval. MS default 2m. | `string` | `"2m"` | no |
| service\_cidr | n/a | `string` | `"172.16.0.0/16"` | no |
| sku\_tier | n/a | `string` | `"Standard"` | no |
| support\_plan | AKS support plan. 'KubernetesOfficial' = standard 12-month support window. 'AKSLongTermSupport' = 30-month LTS support window (Premium SKU only). | `string` | `"KubernetesOfficial"` | no |
| system\_pool\_auto\_scaling | n/a | `bool` | `false` | no |
| system\_pool\_host\_encryption\_enabled | Encryption at host for the system pool (F-SEC-6-bis pattern). Requires CMK Disk Encryption Set on the sub or platform-managed encryption. | `bool` | `true` | no |
| system\_pool\_max\_count | n/a | `number` | `6` | no |
| system\_pool\_min\_count | n/a | `number` | `3` | no |
| system\_pool\_node\_count | n/a | `number` | `3` | no |
| system\_pool\_only\_critical\_addons\_enabled | Taints the system pool with CriticalAddonsOnly=true:NoSchedule to keep workloads off it. Recommended for prod multi-pool. | `bool` | `true` | no |
| system\_pool\_os\_disk\_size\_gb | n/a | `number` | `100` | no |
| system\_pool\_os\_disk\_type | n/a | `string` | `"Ephemeral"` | no |
| system\_pool\_vm\_size | n/a | `string` | `"Standard_D4ds_v5"` | no |
| tags | ############################################################## TAGS ############################################################## | `map(string)` | `{}` | no |
| upgrade\_max\_surge | n/a | `string` | `"33%"` | no |
| upgrade\_override\_effective\_until | Passthrough to Aks: upgrade\_override.effective\_until (RFC3339). Only used when upgrade\_override\_enabled = true. | `string` | `null` | no |
| upgrade\_override\_enabled | Passthrough to Aks: emit the upgrade\_override block. Leave false for a NEW cluster (emitting it sends effectiveUntil="" -> AKS rejects creation, 400 UnmarshalError). Set true ONLY on a cluster that already carries the setting (upgrade\_override cannot be unset). | `bool` | `false` | no |
| upgrade\_override\_force\_upgrade | Passthrough to Aks: upgrade\_override.force\_upgrade\_enabled. Only effective when upgrade\_override\_enabled = true. Leave false except in exceptional cases. | `bool` | `false` | no |
| user\_node\_pools | Map of additional node pools (workload pools). Key = pool key (≤ 12 chars).<br>Empty = system-only cluster.<br><br>Spot pools: set priority = "Spot" (defaults to "Regular"). When Spot,<br>eviction\_policy and spot\_max\_price take effect; Azure auto-applies the<br>kubernetes.azure.com/scalesetpriority=spot:NoSchedule taint, so workloads<br>must add the matching toleration. Spot pools require autoscaling. | <pre>map(object({<br>    name                        = string<br>    vm_size                     = string<br>    os_disk_type                = optional(string, "Ephemeral")<br>    os_disk_size_gb             = optional(number, 100)<br>    host_encryption_enabled     = optional(bool, true)<br>    auto_scaling_enabled        = optional(bool, true)<br>    node_count                  = optional(number)<br>    min_count                   = optional(number, 1)<br>    max_count                   = optional(number, 3)<br>    zones                       = optional(list(string))<br>    labels                      = optional(map(string), {})<br>    taints                      = optional(list(string), [])<br>    temporary_name_for_rotation = optional(string)<br>    priority                    = optional(string, "Regular")<br>    eviction_policy             = optional(string, "Delete")<br>    spot_max_price              = optional(number, -1)<br>  }))</pre> | `{}` | no |
| vertical\_pod\_autoscaler\_enabled | ############################################################## CLUSTER FEATURES ############################################################## | `bool` | `true` | no |
| web\_app\_routing\_default\_nginx\_controller | Default ingress controller mode: None \| Internal \| External \| AnnotationControlled. null = AnnotationControlled (azurerm default). | `string` | `null` | no |
| web\_app\_routing\_dns\_zone\_ids | Azure DNS zone IDs to integrate (BYO-DNS). Empty list = no DNS integration. | `list(string)` | `[]` | no |
| workload | Workload suffix used in cluster name and naming chains. Default '001' for the first AKS in a sub. | `string` | `"001"` | no |

## Outputs

| Name | Description |
|------|-------------|
| aks\_lock\_id | AKS cluster lock ID (null if var.lock is null) |
| cluster\_fqdn | Private FQDN of the AKS API server. |
| cluster\_id | ─── AKS cluster ───────────────────────────────────────────── |
| cluster\_name | n/a |
| control\_plane\_identity | Control Plane User Assigned Managed Identity used by the AKS cluster. |
| etcd\_key\_id | Versioned KV key ID for etcd CMK. |
| etcd\_key\_versionless\_id | Versionless KV key ID for etcd CMK. Use this in the post-deploy `az aks update --azure-keyvault-kms-key-id` command. |
| key\_vault\_id | ─── Key Vault + etcd CMK ──────────────────────────────────── |
| key\_vault\_name | n/a |
| key\_vault\_uri | n/a |
| kubelet\_identity | Kubelet User Assigned Managed Identity (used by node pools to pull from ACR, read KV secrets, etc.). |
| kv\_private\_endpoint\_id | Resource ID of the Private Endpoint targeting the etcd CMK Key Vault. |
| kv\_private\_endpoint\_ip | Private IP address of the Key Vault Private Endpoint (null until ALZ DINE Policy completes the privateDnsZoneGroup, which doesn't change the NIC IP). |
| kv\_resource\_group\_name | RG hosting the KV + KV PE + etcd CMK. Equal to resource\_group\_name when var.kv\_resource\_group\_name is null (single-RG mode). |
| node\_resource\_group\_name | n/a |
| oidc\_issuer\_url | OIDC issuer URL — feed this into Federated Identity Credentials for Workload Identity. |
| post\_deploy\_az\_cli\_commands | Commands to run AFTER apply to enable KMS v2 + API Server VNet Integration (azurerm v4 limitation). The KMS step is required even when api\_server\_subnet\_id is null if you want Private network\_access on the KV. |
| resource\_group\_name | Cluster RG name (caller-managed). |
| web\_app\_routing\_identity\_client\_id | Client ID of the auto-created UAMI used by the Application Routing addon. |
| web\_app\_routing\_identity\_principal\_id | Principal ID of the auto-created UAMI used by the Application Routing addon (for cross-sub RBAC grants on Azure DNS zones). |
<!-- END_TF_DOCS -->
