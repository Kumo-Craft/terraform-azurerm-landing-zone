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
