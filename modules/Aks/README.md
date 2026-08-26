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
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/Aks?ref=v0.2.65"

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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| null | >= 3.2 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| null | >= 3.2 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [null_resource.enable_kms](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.enable_vnet_integration](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.restart_after_vnet_integration](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster\_identity\_id | User Assigned Managed Identity ID for the cluster | `string` | n/a | yes |
| kubelet\_identity\_client\_id | Kubelet Identity client ID | `string` | n/a | yes |
| kubelet\_identity\_id | Kubelet Managed Identity ID | `string` | n/a | yes |
| kubelet\_identity\_object\_id | Kubelet Identity object ID (principal ID) | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| node\_subnet\_id | Subnet ID for AKS nodes | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| tenant\_id | Azure AD tenant ID for AKS RBAC | `string` | n/a | yes |
| api\_server\_subnet\_id | Dedicated subnet ID for API Server VNet Integration. Null = disabled. | `string` | `null` | no |
| automatic\_upgrade\_channel | Automatic upgrade channel: none, patch, rapid, stable, node-image | `string` | `"stable"` | no |
| availability\_zones | Availability zones | `list(string)` | <pre>[<br>  "1",<br>  "2",<br>  "3"<br>]</pre> | no |
| cost\_analysis\_enabled | Enable AKS Cost Analysis (namespace-level cost breakdown in the Azure<br>Portal). Free, opt-in. Requires sku\_tier = "Standard" or "Premium" —<br>Azure rejects the apply if sku\_tier = "Free". | `bool` | `false` | no |
| disk\_encryption\_set\_id | Resource ID of a customer-managed Disk Encryption Set (DES) used to encrypt<br>the AKS node OS and data disks (and their caches) with a customer-managed key<br>(BYOK). Resolves Checkov CKV\_AZURE\_117.<br><br>Null (default) = Azure platform-managed keys (still encrypted at rest, but<br>Microsoft-managed). To satisfy CKV\_AZURE\_117 / BYOK, pass the ID of a DES you<br>provision OUTSIDE this module (Key Vault + key with soft-delete & purge<br>protection, DES with a managed identity, and Reader access for the AKS cluster<br>identity on the DES). This module intentionally does NOT create the DES — it is<br>a cross-cutting dependency shared with other resources.<br><br>Per Microsoft Learn (https://learn.microsoft.com/azure/aks/azure-disk-customer-managed-keys):<br>OS-disk CMK encryption can only be enabled at cluster CREATION time. The DES<br>must be in the same region as the cluster. Changing this forces a new cluster<br>(ForceNew in the azurerm schema). | `string` | `null` | no |
| dns\_prefix | Cluster DNS prefix. If null, derived from name. | `string` | `null` | no |
| dns\_service\_ip | Kubernetes DNS service IP (within service\_cidr) | `string` | `"172.16.0.10"` | no |
| enable\_container\_insights | Enable Container Insights via the oms\_agent addon (installs the ama-logs<br>DaemonSet on every node). Uses MSI auth (`msi_auth_for_monitoring_enabled =<br>true`) — the modern Microsoft-recommended pattern for AKS Terraform<br>(https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable,<br>"Terraform" tab, updated 2026-04-17).<br><br>When true, AKS auto-provisions a default DCR/DCRA pair tied to<br>`log_analytics_workspace_id`. Callers typically also deploy an explicit<br>ContainerInsightsCollector module for custom streams (ContainerLogV2,<br>KubeEvents, KubePodInventory, etc.) — those override/complement the<br>auto-created defaults.<br><br>Requires `log_analytics_workspace_id` to be set. | `bool` | `false` | no |
| enable\_secrets\_store\_csi\_driver | Enable the `azure-keyvault-secrets-provider` addon (Secrets Store CSI<br>Driver + Azure provider) on the cluster. Installs the<br>`secrets-store-csi-driver` + `secrets-store-provider-azure` DaemonSets<br>in `kube-system`.<br><br>Modern Microsoft Terraform pattern (csi-secrets-store-driver.md, updated<br>2026-05-05).<br><br>AKS auto-creates a UAMI named `azurekeyvaultsecretsprovider-<cluster>`<br>in the node RG (cannot be opted out). This module does NOT grant any<br>Key Vault RBAC to that identity — apps are expected to provide their<br>own access via Microsoft Entra Workload Identity (per-pod federated<br>credentials), which the cluster already supports (oidc\_issuer\_enabled<br>+ workload\_identity\_enabled). | `bool` | `false` | no |
| enable\_web\_app\_routing | Enable the AKS Application Routing addon (managed nginx ingress<br>controller). Modern Microsoft Terraform pattern for ingress —<br>replaces AGIC; complementary to AGC (AGC handles public-only ingress,<br>Application Routing supports both public + private via the<br>default\_nginx\_controller knob).<br><br>When true, AKS installs the ingress-nginx-controller in the<br>`app-routing-system` namespace and creates the<br>`webapprouting.kubernetes.azure.com` IngressClass. Apps consume it<br>via standard k8s Ingress resources. | `bool` | `false` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| image\_cleaner\_enabled | Enable Image Cleaner to remove unused images | `bool` | `false` | no |
| image\_cleaner\_interval\_hours | Interval in hours for image cleanup | `number` | `48` | no |
| keda\_enabled | Enable KEDA (Kubernetes Event-Driven Autoscaler) addon. | `bool` | `false` | no |
| kms\_key\_id | Key Vault key ID for KMS v2 encryption. Null = no KMS. | `string` | `null` | no |
| kms\_key\_vault\_id | Key Vault resource ID for KMS. Required when key\_vault\_network\_access = Private. | `string` | `null` | no |
| kubernetes\_version | Kubernetes version (e.g. 1.30). Null = latest. | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the AKS cluster.<br>Production clusters should use CanNotDelete to protect against<br>accidental deletion (prevent\_destroy = true only protects a single<br>Terraform state; an Azure-side delete bypasses it).<br>Set to null to skip.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Defaults to "lock-<kind>". | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| log\_analytics\_workspace\_id | Log Analytics Workspace ID for Defender and diagnostics | `string` | `null` | no |
| maintenance\_window | AKS maintenance window (day + UTC hours) | <pre>object({<br>    day        = string<br>    hour_start = number<br>    hour_end   = number<br>  })</pre> | `null` | no |
| monitor\_metrics | Configuration for the managed Prometheus (ama-metrics) monitor\_metrics block.<br>When non-null, the block is emitted; when null, the block is omitted entirely.<br><br>- `annotations_allowed` - (Optional) Comma-separated list of Kubernetes annotation<br>  keys that are allowed as metric labels. Restricting this list avoids high-<br>  cardinality label explosion on large clusters.<br>- `labels_allowed` - (Optional) Comma-separated list of Kubernetes label keys<br>  allowed as metric labels. Same cardinality rationale.<br><br>Set to `{}` to enable the addon with no annotation/label filter (equivalent to<br>the former hardcoded `monitor_metrics {}` empty block). Set to null to disable<br>the monitor\_metrics block entirely (e.g. when a customer-managed Prometheus<br>scrape pipeline replaces the managed addon). | <pre>object({<br>    annotations_allowed = optional(string)<br>    labels_allowed      = optional(string)<br>  })</pre> | `{}` | no |
| name | Explicit cluster name. If null, computed automatically. | `string` | `null` | no |
| network\_data\_plane | Dataplane for Azure CNI Overlay: 'azure' (default) or 'cilium'. Cilium<br>dataplane (eBPF, Hubble observability) requires network\_policy = 'cilium'<br>and is GA on AKS since Nov 2024. Microsoft recommends Cilium for new<br>clusters; switching dataplane on an existing cluster requires recreate. | `string` | `"azure"` | no |
| network\_policy | Network policy: azure, calico, cilium | `string` | `"azure"` | no |
| node\_os\_upgrade\_channel | Node OS upgrade channel: Unmanaged, SecurityPatch, NodeImage, None | `string` | `"NodeImage"` | no |
| node\_resource\_group\_name | Node resource group name. If null, computed automatically. | `string` | `null` | no |
| outbound\_type | Outbound type: loadBalancer, userDefinedRouting, managedNATGateway | `string` | `"userDefinedRouting"` | no |
| pod\_cidr | CIDR for pods (overlay) | `string` | `"10.244.0.0/16"` | no |
| private\_cluster\_public\_fqdn\_enabled | When true, AKS publishes a public FQDN that resolves to the private API<br>server IP. Useful for kubectl from machines outside the VNet (still needs<br>VPN/private link for the actual connection — only DNS is public).<br><br>Default null = compute from private\_dns\_zone\_id:<br>  - 'None'         -> true  (no custom DNS zone, public FQDN helps kubectl resolution)<br>  - any other value -> false (custom DNS zone already serves resolution privately)<br><br>Set explicitly to false in production to hide the cluster's existence<br>even from DNS queries. | `bool` | `null` | no |
| private\_dns\_zone\_id | Private DNS Zone ID. 'None' = ALZ policy manages DNS. 'System' = auto in node RG. | `string` | `"None"` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| secrets\_store\_csi\_driver\_rotation\_enabled | Enable secret auto-rotation on the Secrets Store CSI Driver (recommended). | `bool` | `true` | no |
| secrets\_store\_csi\_driver\_rotation\_interval | Polling interval for secret rotation (ISO 8601 duration or Go duration). Microsoft default is 2m. | `string` | `"2m"` | no |
| service\_cidr | CIDR for Kubernetes services | `string` | `"172.16.0.0/16"` | no |
| sku\_tier | SKU tier: Free, Standard, Premium | `string` | `"Standard"` | no |
| subscription\_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | no |
| support\_plan | AKS support plan. 'KubernetesOfficial' = standard 12-month support<br>window. 'AKSLongTermSupport' = 30-month LTS support window (Premium<br>SKU only). Default is KubernetesOfficial for compatibility with<br>Free/Standard tiers. | `string` | `"KubernetesOfficial"` | no |
| system\_pool\_auto\_scaling | Enable autoscaling on the system pool | `bool` | `false` | no |
| system\_pool\_host\_encryption\_enabled | Enables Encryption at Host on the system node pool. Encrypts temp disk,<br>cache, and pagefile at the hypervisor level (complements etcd KMS v2<br>which is cluster-wide). Set to true to satisfy Checkov CKV\_AZURE\_227.<br><br>OPT-IN (default = false) — deliberately NOT forced on. Host-based encryption<br>requires the 'Microsoft.Compute/EncryptionAtHost' feature to be REGISTERED on<br>the target subscription and is only supported on specific VM sizes and regions;<br>it is set at node-pool CREATION time only. Defaulting it to true would break<br>AKS creation on any subscription lacking the feature or using an unsupported<br>VM size/region — so it stays opt-in. Per Microsoft Learn<br>(https://learn.microsoft.com/azure/aks/enable-host-encryption), enable the<br>prerequisite before setting this to true:<br>  az feature register --namespace Microsoft.Compute --name EncryptionAtHost<br>  az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query "properties.state"<br>  az provider register --namespace Microsoft.Compute<br><br>Requires a compatible VM size (Dsv4+, Esv4+, Ddsv5+, etc.) in a region that<br>supports server-side encryption of Azure managed disks.<br>Toggling this flag triggers a rotation of the node pool (surge + drain). | `bool` | `false` | no |
| system\_pool\_max\_count | Maximum nodes (autoscaling) | `number` | `5` | no |
| system\_pool\_min\_count | Minimum nodes (autoscaling) | `number` | `3` | no |
| system\_pool\_node\_count | Node count (when autoscaling is disabled) | `number` | `3` | no |
| system\_pool\_only\_critical\_addons\_enabled | If true, taints the system node pool with CriticalAddonsOnly=true:NoSchedule<br>so only system-critical addons land on it. Set to false in non-prod clusters<br>when third-party agents (Rancher Fleet, Helm operations, etc.) don't tolerate<br>the taint and patching their charts is not desired. | `bool` | `true` | no |
| system\_pool\_os\_disk\_size\_gb | OS disk size in GB | `number` | `128` | no |
| system\_pool\_os\_disk\_type | OS disk type: Ephemeral or Managed | `string` | `"Ephemeral"` | no |
| system\_pool\_vm\_size | VM SKU for the system pool | `string` | `"Standard_D4s_v5"` | no |
| tags | Tags | `map(string)` | `{}` | no |
| upgrade\_max\_surge | Max surge for node upgrades | `string` | `"33%"` | no |
| upgrade\_override\_effective\_until | upgrade\_override.effective\_until — RFC3339 timestamp until which a forced upgrade applies. Only used when upgrade\_override\_enabled = true. Null = provider default (required by the API only when a force upgrade is actually scheduled). | `string` | `null` | no |
| upgrade\_override\_enabled | Emit the upgrade\_override block. Leave false for a NEW cluster: when emitted, azurerm sends effectiveUntil="" and the AKS API rejects creation (400 UnmarshalError). Set true ONLY on a cluster that already carries upgradeSettings.overrideSettings, where `upgrade_override` cannot be unset. | `bool` | `false` | no |
| upgrade\_override\_force\_upgrade | upgrade\_override.force\_upgrade\_enabled — bypass upgrade protections. Only takes effect when upgrade\_override\_enabled = true. Leave false except in exceptional cases. | `bool` | `false` | no |
| user\_node\_pools | A map of user node pool configurations. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>- `name`                        - (Required) Node pool name (max 12 chars, lowercase alphanumeric).<br>- `vm_size`                     - (Required) VM SKU.<br>- `min_count`                   - (Required) Minimum nodes.<br>- `max_count`                   - (Required) Maximum nodes.<br>- `node_count`                  - (Optional) Fixed node count (when autoscaling disabled).<br>- `auto_scaling_enabled`        - (Optional) Enable autoscaling. Defaults to true.<br>- `os_disk_type`                - (Optional) Ephemeral or Managed. Defaults to Ephemeral.<br>- `os_disk_size_gb`             - (Optional) OS disk size in GB.<br>- `zones`                       - (Optional) Availability zones. Defaults to cluster zones.<br>- `labels`                      - (Optional) Node labels.<br>- `taints`                      - (Optional) Node taints.<br>- `temporary_name_for_rotation` - (Optional) Temp name for rotation (max 12 chars).<br>- `host_encryption_enabled`     - (Optional) Enables Encryption at Host on the pool. Defaults to false (opt-in). Set true to satisfy CKV\_AZURE\_227; requires the subscription 'Microsoft.Compute/EncryptionAtHost' feature registered + a supported VM size/region, set at pool creation only. Kept opt-in so AKS creation does not fail where the feature is unavailable.<br>- `priority`                    - (Optional) 'Regular' (default) or 'Spot'. Spot pools cost ~50-90% less but can be evicted at any time. Use for non-critical workloads with proper taints/tolerations.<br>- `eviction_policy`             - (Optional) For Spot pools only: 'Delete' (default) or 'Deallocate'. Delete is recommended.<br>- `spot_max_price`              - (Optional) For Spot pools only: max price per hour, -1 (default) means up to the on-demand price.<br><br>## BREAKING change (v0.2.65)<br>Field `enable_auto_scaling` renamed to `auto_scaling_enabled` to match azurerm 4.x<br>provider schema (`azurerm_kubernetes_cluster_node_pool.auto_scaling_enabled`). The<br>old v3-style name `enable_auto_scaling` is no longer accepted. Callers must rename<br>the field in their var.user\_node\_pools maps. No state migration is needed — this<br>is a variable-shape change only. | <pre>map(object({<br>    name                        = string<br>    vm_size                     = string<br>    min_count                   = number<br>    max_count                   = number<br>    node_count                  = optional(number)<br>    auto_scaling_enabled        = optional(bool, true)<br>    os_disk_type                = optional(string, "Ephemeral")<br>    os_disk_size_gb             = optional(number)<br>    zones                       = optional(list(string))<br>    labels                      = optional(map(string), {})<br>    taints                      = optional(list(string), [])<br>    temporary_name_for_rotation = optional(string)<br>    host_encryption_enabled     = optional(bool, false)<br>    priority                    = optional(string, "Regular")<br>    eviction_policy             = optional(string, "Delete")<br>    spot_max_price              = optional(number, -1)<br>  }))</pre> | `{}` | no |
| vertical\_pod\_autoscaler\_enabled | Enables the Vertical Pod Autoscaler addon (recommender, updater,<br>admission-controller). Per-workload mode is configured via<br>VerticalPodAutoscaler CRDs in Kubernetes:<br>  updateMode: "Off"     -> recommend-only, no mutation (safe dry-run)<br>  updateMode: "Initial" -> apply at pod creation<br>  updateMode: "Auto"    -> resize live (intrusive, kills+recreates pods)<br><br>Enabling the addon is safe — workloads must explicitly opt-in by<br>creating a VPA object. | `bool` | `false` | no |
| web\_app\_routing\_default\_nginx\_controller | Default nginx controller mode. Allowed:<br>  - "None"                 : no default controller (deploy your own NginxIngressController CRD)<br>  - "Internal"             : private LB (internal IP in the cluster VNet)<br>  - "External"             : public LB (Internet-facing)<br>  - "AnnotationControlled" : per-Ingress decision via the<br>    `service.beta.kubernetes.io/azure-load-balancer-internal` annotation<br>    (default behaviour of the addon).<br>Defaults to null → azurerm provider applies "AnnotationControlled". | `string` | `null` | no |
| web\_app\_routing\_dns\_zone\_ids | List of Azure DNS zone IDs to integrate with the addon (BYO-DNS). Empty list = no DNS integration (Ingress hostnames resolved manually). | `list(string)` | `[]` | no |
| workload | Workload name (e.g. 001, apim) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| fqdn | Private FQDN of the cluster |
| host | Cluster endpoint (sensitive) |
| id | AKS cluster ID |
| kube\_config\_raw | Raw kubeconfig (sensitive) |
| kubelet\_identity | Cluster kubelet identity |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | AKS cluster name |
| node\_resource\_group | Node resource group name |
| oidc\_issuer\_url | OIDC issuer URL |
| resource | The complete AKS cluster resource object |
| web\_app\_routing\_identity\_client\_id | Client ID of the auto-created UAMI used by the Application Routing addon. Null when enable\_web\_app\_routing = false. |
| web\_app\_routing\_identity\_principal\_id | Principal (object) ID of the auto-created UAMI used by the Application Routing addon. Null when enable\_web\_app\_routing = false. |
<!-- END_TF_DOCS -->
