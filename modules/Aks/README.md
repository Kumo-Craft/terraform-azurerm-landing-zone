# Aks

Deploys a private Azure Kubernetes Service cluster with Azure CNI Overlay networking, UserAssigned identity, OIDC/Workload Identity, Microsoft Defender, managed Prometheus, Azure Policy add-on, and optional KMS v2 etcd encryption. Supports system and user node pools with autoscaling.

## Breaking changes (v0.2.50)

### `local_account_disabled = true` (SECURITY — hardcoded)

Local Kubernetes accounts are now permanently disabled. The built-in
`clusterAdmin` and `clusterUser` kubeconfig paths are blocked at the
Azure API level. This closes the AAD-RBAC bypass risk: previously a
cluster admin could retrieve a local kubeconfig that bypassed Entra
ID entirely.

**Who is affected**: Any operator or pipeline that uses
`az aks get-credentials --admin` will receive an error from Azure after
the cluster is updated via `terraform apply`.

**Migration**:

1. Remove all uses of `az aks get-credentials --admin`. The `--admin`
   flag is now rejected.
2. Use `az aks get-credentials` (no `--admin`) to obtain an
   Entra ID-authenticated kubeconfig. On first `kubectl` command you
   will be prompted to sign in via the device-code flow.
3. Ensure every human operator and CI/CD service principal holds at
   least the **Azure Kubernetes Service RBAC Cluster Admin** role at
   the cluster scope:
   ```
   az role assignment create \
     --role "Azure Kubernetes Service RBAC Cluster Admin" \
     --assignee <object-id-or-spn-id> \
     --scope <cluster-resource-id>
   ```
4. For headless pipelines (no device-code), configure the service
   principal via `kubelogin` with the `spn` login mode:
   ```
   kubelogin convert-kubeconfig -l spn
   export AAD_SERVICE_PRINCIPAL_CLIENT_ID=<client-id>
   export AAD_SERVICE_PRINCIPAL_CLIENT_SECRET=<client-secret>
   kubectl get nodes
   ```

References:
- CAF AKS secure baseline: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks#identity-and-access-management
- Disable local accounts: https://learn.microsoft.com/azure/aks/manage-local-accounts-managed-azure-ad

## Breaking changes (v0.2.65)

### `user_node_pools[*].auto_scaling_enabled` (RENAMED — BREAKING)

The field `enable_auto_scaling` inside each `user_node_pools` map entry has been
renamed to `auto_scaling_enabled` to match the azurerm 4.x provider schema
(`azurerm_kubernetes_cluster_node_pool.auto_scaling_enabled`). The old v3-style
name `enable_auto_scaling` is no longer accepted by the module variable type.

**Who is affected**: Any caller that passes `enable_auto_scaling` in their
`user_node_pools` map entries.

**Migration**: Rename the field in each pool entry:

```hcl
# Before (v0.2.64 and earlier)
user_node_pools = {
  app = {
    name               = "app"
    vm_size            = "Standard_D4s_v5"
    min_count          = 2
    max_count          = 10
    enable_auto_scaling = true   # <-- old name
  }
}

# After (v0.2.65+)
user_node_pools = {
  app = {
    name                 = "app"
    vm_size              = "Standard_D4s_v5"
    min_count            = 2
    max_count            = 10
    auto_scaling_enabled = true  # <-- new name (matches azurerm 4.x)
  }
}
```

No state migration is needed — this is a variable-shape change only. The
underlying `azurerm_kubernetes_cluster_node_pool` resource argument name
was already correct.

### `default_node_pool` node_count drift when autoscaling enabled (F-5/F-15)

The unconditional `ignore_changes = [node_count]` on both the system pool and
user node pools has been removed. When the cluster autoscaler is active, it
mutates `node_count` out-of-band and Terraform will report drift on the next
plan. This is expected — suppress it in your root module with a targeted
`lifecycle { ignore_changes = [default_node_pool[0].node_count] }` if desired.

### `kms_key_vault_key_id` — use versionless URI (F-10)

When wiring `var.kms_key_id`, callers must supply the **versionless** Key Vault
key URI:

```
https://<vault>.vault.azure.net/keys/<key-name>
```

Do NOT include the version suffix (`/<version-id>`). AKS requires the versionless
form so the service can automatically pick up new key versions after rotation.
Using a versioned URI pins etcd encryption to a single key version; after key
rotation the cluster will fail to decrypt etcd secrets until the URI is manually
updated.

## Usage

### Standalone

```hcl
module "aks" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/Aks?ref=v0.2.65"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "001"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-aks"

  node_subnet_id             = "/subscriptions/.../subnets/snet-api-prod-gwc-nodes"
  cluster_identity_id        = "/subscriptions/.../userAssignedIdentities/id-api-prod-gwc-aks-cp"
  kubelet_identity_id        = "/subscriptions/.../userAssignedIdentities/id-api-prod-gwc-aks-kubelet"
  kubelet_identity_client_id = "00000000-0000-0000-0000-000000000000"
  kubelet_identity_object_id = "00000000-0000-0000-0000-000000000000"
  tenant_id                  = "00000000-0000-0000-0000-000000000000"

  private_dns_zone_id        = "None"
  sku_tier                   = "Standard"
  system_pool_vm_size        = "Standard_D4s_v5"
  outbound_type              = "userDefinedRouting"

  log_analytics_workspace_id = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01"

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/Aks"
}

inputs = {
  subscription_acronym       = include.sub.locals.subscription_acronym
  environment                = include.root.inputs.environment
  region_code                = include.root.inputs.region_code
  workload                   = "001"
  location                   = include.root.inputs.location
  resource_group_name        = dependency.rg.outputs.name
  node_subnet_id             = dependency.subnet.outputs.subnet_ids[include.sub.locals.networks.corp_apimanager.subnets.nodes.name]
  cluster_identity_id        = dependency.id_cp.outputs.id
  kubelet_identity_id        = dependency.id_kubelet.outputs.id
  kubelet_identity_client_id = dependency.id_kubelet.outputs.client_id
  kubelet_identity_object_id = dependency.id_kubelet.outputs.principal_id
  tenant_id                  = include.root.inputs.tenant_id
  private_dns_zone_id        = "None"
  log_analytics_workspace_id = dependency.law.outputs.id
  tags                       = include.root.inputs.common_tags
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
| name | Explicit cluster name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload suffix | `string` | `null` | No |
| dns_prefix | DNS prefix. If null, derived from name. | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| node_subnet_id | Subnet ID for AKS nodes | `string` | -- | Yes |
| cluster_identity_id | User Assigned Managed Identity ID for the cluster | `string` | -- | Yes |
| kubelet_identity_id | Kubelet Managed Identity ID | `string` | -- | Yes |
| kubelet_identity_client_id | Kubelet Identity client ID | `string` | -- | Yes |
| kubelet_identity_object_id | Kubelet Identity object ID (principal ID) | `string` | -- | Yes |
| tenant_id | Azure AD tenant ID | `string` | -- | Yes |
| kubernetes_version | Kubernetes version (e.g. 1.30) | `string` | `null` | No |
| sku_tier | SKU tier: Free, Standard, Premium | `string` | `"Standard"` | No |
| node_resource_group_name | Node resource group name. If null, auto-computed. | `string` | `null` | No |
| automatic_upgrade_channel | Auto upgrade channel: none, patch, rapid, stable, node-image | `string` | `"stable"` | No |
| private_dns_zone_id | Private DNS Zone ID. Use `"None"` when ALZ policy manages the zone. | `string` | `"None"` | No |
| api_server_subnet_id | Subnet ID for API Server VNet Integration. Null = disabled. | `string` | `null` | No |
| network_policy | Network policy: azure, calico, cilium | `string` | `"azure"` | No |
| pod_cidr | CIDR for pods (overlay) | `string` | `"10.244.0.0/16"` | No |
| service_cidr | CIDR for Kubernetes services | `string` | `"172.16.0.0/16"` | No |
| dns_service_ip | Kubernetes DNS service IP (within service_cidr) | `string` | `"172.16.0.10"` | No |
| outbound_type | Outbound type: loadBalancer, userDefinedRouting, managedNATGateway | `string` | `"userDefinedRouting"` | No |
| system_pool_vm_size | VM SKU for the system pool | `string` | `"Standard_D4s_v5"` | No |
| system_pool_node_count | Node count (when autoscaling is disabled) | `number` | `3` | No |
| system_pool_auto_scaling | Enable autoscaling on the system pool | `bool` | `false` | No |
| system_pool_min_count | Minimum nodes (autoscaling) | `number` | `3` | No |
| system_pool_max_count | Maximum nodes (autoscaling) | `number` | `5` | No |
| system_pool_os_disk_type | OS disk type: Ephemeral, Managed | `string` | `"Ephemeral"` | No |
| system_pool_os_disk_size_gb | OS disk size in GB | `number` | `128` | No |
| availability_zones | Availability zones | `list(string)` | `["1", "2", "3"]` | No |
| upgrade_max_surge | Max surge for node upgrades | `string` | `"33%"` | No |
| user_node_pools | Map of user node pool configurations. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| maintenance_window | AKS maintenance window (day + UTC hours) | `object({ day = string, hour_start = number, hour_end = number })` | `null` | No |
| image_cleaner_enabled | Enable Image Cleaner to remove unused images | `bool` | `false` | No |
| image_cleaner_interval_hours | Interval in hours for image cleanup | `number` | `48` | No |
| node_os_upgrade_channel | Node OS upgrade channel: Unmanaged, SecurityPatch, NodeImage, None | `string` | `"NodeImage"` | No |
| kms_key_id | Key Vault key ID for KMS v2 encryption. Null = no KMS. | `string` | `null` | No |
| kms_key_vault_id | Key Vault resource ID for KMS. Required when keyVaultNetworkAccess = Private. | `string` | `null` | No |
| log_analytics_workspace_id | Log Analytics Workspace ID for Defender and Container Insights | `string` | `null` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | AKS cluster ID |
| name | AKS cluster name |
| fqdn | Private FQDN of the cluster |
| oidc_issuer_url | OIDC issuer URL |
| node_resource_group | Node resource group name |
| kubelet_identity | Kubelet identity of the cluster |
| resource | Complete AKS cluster resource object |
| kube_config_raw | Raw kubeconfig (sensitive) |
| host | Cluster endpoint (sensitive) |
