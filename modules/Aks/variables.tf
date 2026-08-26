###############################################################
# MODULE: Aks - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Explicit cluster name. If null, computed automatically."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }

  # F-6: AKS dns_prefix is derived from var.name (hyphens stripped). Azure rejects
  # a dns_prefix > 54 characters. The Naming module stays safe automatically (prefix
  # rules enforce short names); this guard catches callers who pass var.name directly.
  validation {
    condition     = var.name == null || length(var.name) <= 54
    error_message = "var.name must be at most 54 characters (Azure dns_prefix limit derived from name)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. api, mgm)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name (e.g. 001, apim)"

  validation {
    condition     = var.workload == null || can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

variable "dns_prefix" {
  type        = string
  default     = null
  description = "Cluster DNS prefix. If null, derived from name."
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

variable "node_subnet_id" {
  type        = string
  description = "Subnet ID for AKS nodes"
  nullable    = false
}

variable "cluster_identity_id" {
  type        = string
  description = "User Assigned Managed Identity ID for the cluster"
  nullable    = false
}

variable "kubelet_identity_id" {
  type        = string
  description = "Kubelet Managed Identity ID"
  nullable    = false
}

variable "kubelet_identity_client_id" {
  type        = string
  description = "Kubelet Identity client ID"
  nullable    = false
}

variable "kubelet_identity_object_id" {
  type        = string
  description = "Kubelet Identity object ID (principal ID)"
  nullable    = false
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID for AKS RBAC"
  nullable    = false
}

###############################################################
# CLUSTER CONFIGURATION
###############################################################
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version (e.g. 1.30). Null = latest."
  default     = null
}

variable "sku_tier" {
  type        = string
  description = "SKU tier: Free, Standard, Premium"
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard, or Premium."
  }
}

variable "node_resource_group_name" {
  type        = string
  default     = null
  description = "Node resource group name. If null, computed automatically."
}

variable "automatic_upgrade_channel" {
  type        = string
  description = "Automatic upgrade channel: none, patch, rapid, stable, node-image"
  default     = "stable"

  validation {
    condition     = contains(["none", "patch", "rapid", "stable", "node-image"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be one of: none, patch, rapid, stable, node-image."
  }
}

variable "upgrade_override_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Emit the upgrade_override block. Leave false for a NEW cluster: when emitted, azurerm sends effectiveUntil=\"\" and the AKS API rejects creation (400 UnmarshalError). Set true ONLY on a cluster that already carries upgradeSettings.overrideSettings, where `upgrade_override` cannot be unset."
}

variable "upgrade_override_force_upgrade" {
  type        = bool
  default     = false
  nullable    = false
  description = "upgrade_override.force_upgrade_enabled — bypass upgrade protections. Only takes effect when upgrade_override_enabled = true. Leave false except in exceptional cases."
}

variable "upgrade_override_effective_until" {
  type        = string
  default     = null
  description = "upgrade_override.effective_until — RFC3339 timestamp until which a forced upgrade applies. Only used when upgrade_override_enabled = true. Null = provider default (required by the API only when a force upgrade is actually scheduled)."
}

###############################################################
# PRIVATE CLUSTER
###############################################################
variable "private_dns_zone_id" {
  type        = string
  description = "Private DNS Zone ID. 'None' = ALZ policy manages DNS. 'System' = auto in node RG."
  default     = "None"
}

variable "private_cluster_public_fqdn_enabled" {
  type        = bool
  description = <<-EOT
  When true, AKS publishes a public FQDN that resolves to the private API
  server IP. Useful for kubectl from machines outside the VNet (still needs
  VPN/private link for the actual connection — only DNS is public).

  Default null = compute from private_dns_zone_id:
    - 'None'         -> true  (no custom DNS zone, public FQDN helps kubectl resolution)
    - any other value -> false (custom DNS zone already serves resolution privately)

  Set explicitly to false in production to hide the cluster's existence
  even from DNS queries.
  EOT
  default     = null
}

variable "api_server_subnet_id" {
  type        = string
  description = "Dedicated subnet ID for API Server VNet Integration. Null = disabled."
  default     = null
}

###############################################################
# NETWORK PROFILE — Azure CNI Overlay
###############################################################
variable "network_policy" {
  type        = string
  description = "Network policy: azure, calico, cilium"
  default     = "azure"

  validation {
    condition     = contains(["azure", "calico", "cilium"], var.network_policy)
    error_message = "network_policy must be azure, calico, or cilium."
  }
}

variable "network_data_plane" {
  type        = string
  description = <<-EOT
  Dataplane for Azure CNI Overlay: 'azure' (default) or 'cilium'. Cilium
  dataplane (eBPF, Hubble observability) requires network_policy = 'cilium'
  and is GA on AKS since Nov 2024. Microsoft recommends Cilium for new
  clusters; switching dataplane on an existing cluster requires recreate.
  EOT
  default     = "azure"

  validation {
    condition     = contains(["azure", "cilium"], var.network_data_plane)
    error_message = "network_data_plane must be 'azure' or 'cilium'."
  }

  validation {
    condition     = var.network_data_plane != "cilium" || var.network_policy == "cilium"
    error_message = "network_data_plane = 'cilium' requires network_policy = 'cilium'."
  }
}

variable "pod_cidr" {
  type        = string
  description = "CIDR for pods (overlay)"
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  type        = string
  description = "CIDR for Kubernetes services"
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  type        = string
  description = "Kubernetes DNS service IP (within service_cidr)"
  default     = "172.16.0.10"
}

variable "outbound_type" {
  type        = string
  description = "Outbound type: loadBalancer, userDefinedRouting, managedNATGateway"
  default     = "userDefinedRouting"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer, userDefinedRouting, or managedNATGateway."
  }
}

###############################################################
# SYSTEM NODE POOL
###############################################################
variable "system_pool_vm_size" {
  type        = string
  description = "VM SKU for the system pool"
  default     = "Standard_D4s_v5"
}

variable "system_pool_node_count" {
  type        = number
  description = "Node count (when autoscaling is disabled)"
  default     = 3
}

variable "system_pool_auto_scaling" {
  type        = bool
  description = "Enable autoscaling on the system pool"
  default     = false
}

variable "system_pool_min_count" {
  type        = number
  description = "Minimum nodes (autoscaling)"
  default     = 3
}

variable "system_pool_max_count" {
  type        = number
  description = "Maximum nodes (autoscaling)"
  default     = 5
}

variable "system_pool_os_disk_type" {
  type        = string
  description = "OS disk type: Ephemeral or Managed"
  default     = "Ephemeral"

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.system_pool_os_disk_type)
    error_message = "system_pool_os_disk_type must be Ephemeral or Managed."
  }
}

variable "system_pool_os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 128
}

variable "system_pool_only_critical_addons_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
  If true, taints the system node pool with CriticalAddonsOnly=true:NoSchedule
  so only system-critical addons land on it. Set to false in non-prod clusters
  when third-party agents (Rancher Fleet, Helm operations, etc.) don't tolerate
  the taint and patching their charts is not desired.
  EOT
}

variable "system_pool_host_encryption_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
  Enables Encryption at Host on the system node pool. Encrypts temp disk,
  cache, and pagefile at the hypervisor level (complements etcd KMS v2
  which is cluster-wide). Set to true to satisfy Checkov CKV_AZURE_227.

  OPT-IN (default = false) — deliberately NOT forced on. Host-based encryption
  requires the 'Microsoft.Compute/EncryptionAtHost' feature to be REGISTERED on
  the target subscription and is only supported on specific VM sizes and regions;
  it is set at node-pool CREATION time only. Defaulting it to true would break
  AKS creation on any subscription lacking the feature or using an unsupported
  VM size/region — so it stays opt-in. Per Microsoft Learn
  (https://learn.microsoft.com/azure/aks/enable-host-encryption), enable the
  prerequisite before setting this to true:
    az feature register --namespace Microsoft.Compute --name EncryptionAtHost
    az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query "properties.state"
    az provider register --namespace Microsoft.Compute

  Requires a compatible VM size (Dsv4+, Esv4+, Ddsv5+, etc.) in a region that
  supports server-side encryption of Azure managed disks.
  Toggling this flag triggers a rotation of the node pool (surge + drain).
  EOT
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones"
  default     = ["1", "2", "3"]
}

variable "upgrade_max_surge" {
  type        = string
  description = "Max surge for node upgrades"
  default     = "33%"
}

###############################################################
# USER NODE POOLS
###############################################################
variable "user_node_pools" {
  description = <<-EOT
  A map of user node pool configurations. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `name`                        - (Required) Node pool name (max 12 chars, lowercase alphanumeric).
  - `vm_size`                     - (Required) VM SKU.
  - `min_count`                   - (Required) Minimum nodes.
  - `max_count`                   - (Required) Maximum nodes.
  - `node_count`                  - (Optional) Fixed node count (when autoscaling disabled).
  - `auto_scaling_enabled`        - (Optional) Enable autoscaling. Defaults to true.
  - `os_disk_type`                - (Optional) Ephemeral or Managed. Defaults to Ephemeral.
  - `os_disk_size_gb`             - (Optional) OS disk size in GB.
  - `zones`                       - (Optional) Availability zones. Defaults to cluster zones.
  - `labels`                      - (Optional) Node labels.
  - `taints`                      - (Optional) Node taints.
  - `temporary_name_for_rotation` - (Optional) Temp name for rotation (max 12 chars).
  - `host_encryption_enabled`     - (Optional) Enables Encryption at Host on the pool. Defaults to false (opt-in). Set true to satisfy CKV_AZURE_227; requires the subscription 'Microsoft.Compute/EncryptionAtHost' feature registered + a supported VM size/region, set at pool creation only. Kept opt-in so AKS creation does not fail where the feature is unavailable.
  - `priority`                    - (Optional) 'Regular' (default) or 'Spot'. Spot pools cost ~50-90% less but can be evicted at any time. Use for non-critical workloads with proper taints/tolerations.
  - `eviction_policy`             - (Optional) For Spot pools only: 'Delete' (default) or 'Deallocate'. Delete is recommended.
  - `spot_max_price`              - (Optional) For Spot pools only: max price per hour, -1 (default) means up to the on-demand price.

  ## BREAKING change (v0.2.65)
  Field `enable_auto_scaling` renamed to `auto_scaling_enabled` to match azurerm 4.x
  provider schema (`azurerm_kubernetes_cluster_node_pool.auto_scaling_enabled`). The
  old v3-style name `enable_auto_scaling` is no longer accepted. Callers must rename
  the field in their var.user_node_pools maps. No state migration is needed — this
  is a variable-shape change only.
  EOT
  type = map(object({
    name                        = string
    vm_size                     = string
    min_count                   = number
    max_count                   = number
    node_count                  = optional(number)
    auto_scaling_enabled        = optional(bool, true)
    os_disk_type                = optional(string, "Ephemeral")
    os_disk_size_gb             = optional(number)
    zones                       = optional(list(string))
    labels                      = optional(map(string), {})
    taints                      = optional(list(string), [])
    temporary_name_for_rotation = optional(string)
    host_encryption_enabled     = optional(bool, false)
    priority                    = optional(string, "Regular")
    eviction_policy             = optional(string, "Delete")
    spot_max_price              = optional(number, -1)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for p in var.user_node_pools : contains(["Regular", "Spot"], p.priority)
    ])
    error_message = "user_node_pools[*].priority must be 'Regular' or 'Spot'."
  }

  validation {
    condition = alltrue([
      for p in var.user_node_pools : contains(["Delete", "Deallocate"], p.eviction_policy)
    ])
    error_message = "user_node_pools[*].eviction_policy must be 'Delete' or 'Deallocate'."
  }

  validation {
    condition = alltrue([
      for p in var.user_node_pools :
      p.priority == "Regular" || p.auto_scaling_enabled == true
    ])
    error_message = "Spot user node pools must have auto_scaling_enabled = true (Spot nodes are evicted at any time, autoscaler must repair the pool)."
  }
}

###############################################################
# MAINTENANCE, IMAGE CLEANER, NODE OS UPGRADE
###############################################################
variable "maintenance_window" {
  description = "AKS maintenance window (day + UTC hours)"
  type = object({
    day        = string
    hour_start = number
    hour_end   = number
  })
  default = null
}

variable "image_cleaner_enabled" {
  type        = bool
  description = "Enable Image Cleaner to remove unused images"
  default     = false
}

variable "vertical_pod_autoscaler_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
  Enables the Vertical Pod Autoscaler addon (recommender, updater,
  admission-controller). Per-workload mode is configured via
  VerticalPodAutoscaler CRDs in Kubernetes:
    updateMode: "Off"     -> recommend-only, no mutation (safe dry-run)
    updateMode: "Initial" -> apply at pod creation
    updateMode: "Auto"    -> resize live (intrusive, kills+recreates pods)

  Enabling the addon is safe — workloads must explicitly opt-in by
  creating a VPA object.
  EOT
}

variable "keda_enabled" {
  type        = bool
  default     = false
  description = "Enable KEDA (Kubernetes Event-Driven Autoscaler) addon."
}

variable "image_cleaner_interval_hours" {
  type        = number
  description = "Interval in hours for image cleanup"
  default     = 48
}

variable "cost_analysis_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
  Enable AKS Cost Analysis (namespace-level cost breakdown in the Azure
  Portal). Free, opt-in. Requires sku_tier = "Standard" or "Premium" —
  Azure rejects the apply if sku_tier = "Free".
  EOT
}

variable "support_plan" {
  description = <<-EOT
  AKS support plan. 'KubernetesOfficial' = standard 12-month support
  window. 'AKSLongTermSupport' = 30-month LTS support window (Premium
  SKU only). Default is KubernetesOfficial for compatibility with
  Free/Standard tiers.
  EOT
  type        = string
  default     = "KubernetesOfficial"
  nullable    = false

  validation {
    condition     = contains(["KubernetesOfficial", "AKSLongTermSupport"], var.support_plan)
    error_message = "support_plan must be 'KubernetesOfficial' or 'AKSLongTermSupport'."
  }
}

variable "node_os_upgrade_channel" {
  type        = string
  description = "Node OS upgrade channel: Unmanaged, SecurityPatch, NodeImage, None"
  default     = "NodeImage"

  validation {
    condition     = contains(["Unmanaged", "SecurityPatch", "NodeImage", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be Unmanaged, SecurityPatch, NodeImage, or None."
  }
}

###############################################################
# DISK ENCRYPTION SET (CMK for node OS + data disks) — CKV_AZURE_117
###############################################################
variable "disk_encryption_set_id" {
  type        = string
  default     = null
  description = <<-EOT
  Resource ID of a customer-managed Disk Encryption Set (DES) used to encrypt
  the AKS node OS and data disks (and their caches) with a customer-managed key
  (BYOK). Resolves Checkov CKV_AZURE_117.

  Null (default) = Azure platform-managed keys (still encrypted at rest, but
  Microsoft-managed). To satisfy CKV_AZURE_117 / BYOK, pass the ID of a DES you
  provision OUTSIDE this module (Key Vault + key with soft-delete & purge
  protection, DES with a managed identity, and Reader access for the AKS cluster
  identity on the DES). This module intentionally does NOT create the DES — it is
  a cross-cutting dependency shared with other resources.

  Per Microsoft Learn (https://learn.microsoft.com/azure/aks/azure-disk-customer-managed-keys):
  OS-disk CMK encryption can only be enabled at cluster CREATION time. The DES
  must be in the same region as the cluster. Changing this forces a new cluster
  (ForceNew in the azurerm schema).
  EOT
}

###############################################################
# KMS V2 ENCRYPTION
###############################################################
variable "kms_key_id" {
  type        = string
  description = "Key Vault key ID for KMS v2 encryption. Null = no KMS."
  default     = null
}

variable "kms_key_vault_id" {
  type        = string
  description = "Key Vault resource ID for KMS. Required when key_vault_network_access = Private."
  default     = null

  validation {
    condition     = !(var.kms_key_id != null && var.api_server_subnet_id != null) || var.kms_key_vault_id != null
    error_message = "kms_key_vault_id is required when both kms_key_id and api_server_subnet_id are set (null_resource.enable_kms provisioner needs the Key Vault resource ID)."
  }
}

###############################################################
# MANAGED PROMETHEUS
###############################################################
variable "monitor_metrics" {
  description = <<-EOT
  Configuration for the managed Prometheus (ama-metrics) monitor_metrics block.
  When non-null, the block is emitted; when null, the block is omitted entirely.

  - `annotations_allowed` - (Optional) Comma-separated list of Kubernetes annotation
    keys that are allowed as metric labels. Restricting this list avoids high-
    cardinality label explosion on large clusters.
  - `labels_allowed` - (Optional) Comma-separated list of Kubernetes label keys
    allowed as metric labels. Same cardinality rationale.

  Set to `{}` to enable the addon with no annotation/label filter (equivalent to
  the former hardcoded `monitor_metrics {}` empty block). Set to null to disable
  the monitor_metrics block entirely (e.g. when a customer-managed Prometheus
  scrape pipeline replaces the managed addon).
  EOT
  type = object({
    annotations_allowed = optional(string)
    labels_allowed      = optional(string)
  })
  default = {}
}

###############################################################
# MONITORING
###############################################################
variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics Workspace ID for Defender and diagnostics"
  default     = null
}

variable "enable_container_insights" {
  type        = bool
  description = <<-EOT
  Enable Container Insights via the oms_agent addon (installs the ama-logs
  DaemonSet on every node). Uses MSI auth (`msi_auth_for_monitoring_enabled =
  true`) — the modern Microsoft-recommended pattern for AKS Terraform
  (https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable,
  "Terraform" tab, updated 2026-04-17).

  When true, AKS auto-provisions a default DCR/DCRA pair tied to
  `log_analytics_workspace_id`. Callers typically also deploy an explicit
  ContainerInsightsCollector module for custom streams (ContainerLogV2,
  KubeEvents, KubePodInventory, etc.) — those override/complement the
  auto-created defaults.

  Requires `log_analytics_workspace_id` to be set.
  EOT
  default     = false
}

variable "enable_secrets_store_csi_driver" {
  type        = bool
  description = <<-EOT
  Enable the `azure-keyvault-secrets-provider` addon (Secrets Store CSI
  Driver + Azure provider) on the cluster. Installs the
  `secrets-store-csi-driver` + `secrets-store-provider-azure` DaemonSets
  in `kube-system`.

  Modern Microsoft Terraform pattern (csi-secrets-store-driver.md, updated
  2026-05-05).

  AKS auto-creates a UAMI named `azurekeyvaultsecretsprovider-<cluster>`
  in the node RG (cannot be opted out). This module does NOT grant any
  Key Vault RBAC to that identity — apps are expected to provide their
  own access via Microsoft Entra Workload Identity (per-pod federated
  credentials), which the cluster already supports (oidc_issuer_enabled
  + workload_identity_enabled).
  EOT
  default     = false
}

variable "secrets_store_csi_driver_rotation_enabled" {
  type        = bool
  description = "Enable secret auto-rotation on the Secrets Store CSI Driver (recommended)."
  default     = true
}

variable "secrets_store_csi_driver_rotation_interval" {
  type        = string
  description = "Polling interval for secret rotation (ISO 8601 duration or Go duration). Microsoft default is 2m."
  default     = "2m"
}

###############################################################
# TAGS
variable "enable_web_app_routing" {
  type        = bool
  description = <<-EOT
  Enable the AKS Application Routing addon (managed nginx ingress
  controller). Modern Microsoft Terraform pattern for ingress —
  replaces AGIC; complementary to AGC (AGC handles public-only ingress,
  Application Routing supports both public + private via the
  default_nginx_controller knob).

  When true, AKS installs the ingress-nginx-controller in the
  `app-routing-system` namespace and creates the
  `webapprouting.kubernetes.azure.com` IngressClass. Apps consume it
  via standard k8s Ingress resources.
  EOT
  default     = false
}

variable "web_app_routing_dns_zone_ids" {
  type        = list(string)
  description = "List of Azure DNS zone IDs to integrate with the addon (BYO-DNS). Empty list = no DNS integration (Ingress hostnames resolved manually)."
  default     = []
}

variable "web_app_routing_default_nginx_controller" {
  type        = string
  description = <<-EOT
  Default nginx controller mode. Allowed:
    - "None"                 : no default controller (deploy your own NginxIngressController CRD)
    - "Internal"             : private LB (internal IP in the cluster VNet)
    - "External"             : public LB (Internet-facing)
    - "AnnotationControlled" : per-Ingress decision via the
      `service.beta.kubernetes.io/azure-load-balancer-internal` annotation
      (default behaviour of the addon).
  Defaults to null → azurerm provider applies "AnnotationControlled".
  EOT
  default     = null

  validation {
    condition     = var.web_app_routing_default_nginx_controller == null || contains(["None", "Internal", "External", "AnnotationControlled"], coalesce(var.web_app_routing_default_nginx_controller, "AnnotationControlled"))
    error_message = "web_app_routing_default_nginx_controller must be one of: None, Internal, External, AnnotationControlled."
  }
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = <<-EOT
  Optional resource lock (CanNotDelete / ReadOnly) on the AKS cluster.
  Production clusters should use CanNotDelete to protect against
  accidental deletion (prevent_destroy = true only protects a single
  Terraform state; an Azure-side delete bypasses it).
  Set to null to skip.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Defaults to "lock-<kind>".
  EOT
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}

###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags"
  default     = {}
  nullable    = false
}
