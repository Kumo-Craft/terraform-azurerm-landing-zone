###############################################################
# MODULE: AksStack — Variables
#
# Bundle: RG (optional) + 2 UAMIs (cluster + kubelet) + KV
# (etcd CMK) + KV-Key + AKS cluster + user node pools + RBAC.
#
# Replaces 7 separate Terragrunt deployments with 1.
# Designed against Microsoft AKS best practices: private cluster,
# Azure CNI Overlay, KMS v2 etcd, OIDC + Workload Identity,
# AAD RBAC, Container Insights, Image Cleaner, Auto-upgrade.
###############################################################

###############################################################
# NAMING
###############################################################
variable "subscription_acronym" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload suffix used in cluster name and naming chains. Default '001' for the first AKS in a sub."
  default     = "001"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,15}$", var.workload))
    error_message = "workload must be 1-16 lowercase alphanumerics or hyphens."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type     = string
  nullable = false
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID for AAD RBAC + KV"
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a valid GUID."
  }
}

variable "node_subnet_id" {
  type        = string
  description = "Subnet ID for AKS nodes (must be a /24 minimum, no NSG-required policy violation since you should provision via SubnetWithNsg or NetworkStack)."
  nullable    = false
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.node_subnet_id))
    error_message = "node_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "api_server_subnet_id" {
  type        = string
  description = "Optional subnet ID for API Server VNet Integration. When set, KMS v2 + VNet integration must be enabled out-of-band via 'az aks update' (azurerm v4 limitation). Set to null to keep API Server fully managed."
  default     = null
}

variable "kv_pe_subnet_id" {
  type        = string
  description = <<-EOT
  Subnet ID where the Private Endpoint targeting the etcd CMK Key Vault is
  deployed. The PE exposes subresource 'vault'. The privateDnsZoneGroup is
  created automatically by ALZ DINE Policy (cross-sub privatelink.vaultcore.azure.net
  zone in connectivity), so this stack does not pass private_dns_zone_ids.

  Mandatory: every KV in this LZ must have a PE — KV is deployed with
  public_network_access_enabled = false and the AKS control plane (or any
  caller) needs the PE to reach the etcd CMK for KMS v2.
  EOT
  nullable    = false
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.kv_pe_subnet_id))
    error_message = "kv_pe_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "kv_pe_dns_propagation_wait" {
  type        = string
  description = <<-EOT
  Sleep duration after KV Private Endpoint creation, before the AKS cluster
  is created. Gives ALZ DINE Policy time to deploy the privateDnsZoneGroup
  (cross-sub privatelink.vaultcore.azure.net A record) so the AKS control
  plane can resolve the KV via private IP at KMS-attach time.

  Format: Go duration string ('30s', '3m', '5m'). Set '0s' to disable.
  Default '5m' covers DINE latency in most tenants. Increase if you observe
  KMS-unreachable errors at first apply.

  Only sleeps on initial PE creation — subsequent applies are unaffected.
  EOT
  default     = "5m"
}

###############################################################
# RESOURCE GROUP
###############################################################
variable "resource_group_name" {
  type        = string
  description = "Name of the pre-existing resource group for the AKS cluster and UAMIs. Caller-managed (AksStack no longer creates the RG)."
  nullable    = false
  validation {
    condition     = can(regex("^[a-zA-Z0-9._()\\-]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be 1-90 characters: letters, digits, periods, underscores, parentheses, or hyphens."
  }
}

variable "node_resource_group_name" {
  type        = string
  description = "AKS node resource group name (managed by AKS). Default 'rg-{prefix}-aks-nodes'."
  default     = null
}

variable "kv_resource_group_name" {
  type        = string
  description = <<-EOT
  Optional separate resource group for the etcd CMK Key Vault, its Private
  Endpoint and the etcd KV Key. Default null = same RG as the cluster.

  Recommended in production: a dedicated RG with a CanNotDelete lock isolates
  the cryptographic material from the compute lifecycle. Loss of the etcd CMK
  KV permanently breaks the cluster (KMS v2 cannot decrypt etcd state), so
  separating its lifecycle from the (more frequently destroyed) compute RG
  is sound separation of duties + extra safeguard.
  EOT
  default     = null
}

###############################################################
# KEY VAULT (for etcd CMK + workload secrets)
###############################################################
variable "kv_workload" {
  type        = string
  description = "Workload segment in the KV name (kv-{prefix}-{kv_workload}). Default 'kv'."
  default     = "kv"
}

variable "kv_suffix" {
  type        = string
  description = "Optional suffix appended to the computed KV name (e.g. '002'). KV total name must stay ≤ 24 chars."
  default     = null
}

variable "kv_sku_name" {
  type        = string
  description = "Key Vault SKU. 'premium' is required for HSM-backed keys (recommended for etcd CMK)."
  default     = "premium"
  validation {
    condition     = contains(["standard", "premium"], var.kv_sku_name)
    error_message = "kv_sku_name must be 'standard' or 'premium'."
  }
}

variable "kv_soft_delete_retention_days" {
  type    = number
  default = 90
  validation {
    condition     = var.kv_soft_delete_retention_days >= 7 && var.kv_soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be 7-90."
  }
}

variable "kv_admin_principal_ids" {
  type        = list(string)
  description = "Object IDs of principals (admins, deployer SP, AAD groups) granted Key Vault Administrator at the KV scope. Required at least to create the etcd CMK. Empty list = only the kubelet UAMI (Crypto User) gets access."
  default     = []
}

variable "kms_v2_enabled" {
  type        = bool
  description = <<-EOT
  Whether to wire the etcd CMK into the AKS cluster. Default false because:

  - When true AND api_server_subnet_id is null: the Aks module creates an
    inline `key_management_service` block with `key_vault_network_access =
    "Private"`. The cluster control plane MUST reach the KV via private
    networking — typically a PE on the KV in the workload sub. Without that
    PE, the apply fails at AKS create time.
  - When true AND api_server_subnet_id is set: the inline block stays empty
    (Aks module gate), KMS must be enabled out-of-band via `az aks update`
    post-deploy (azurerm v4 limitation).
  - When false: the etcd CMK is still created (cheap, forward-compatible),
    but AKS is deployed without KMS v2. Enable later via `az aks update`
    once the KV PE / VNet integration is in place.

  Recommendation: deploy with kms_v2_enabled = false on greenfield workloads,
  add the KV PE separately, then flip to true (or run the post-deploy CLI).
  EOT
  default     = false
}

variable "etcd_key_rotation_policy" {
  description = "Rotation policy on the etcd CMK. Default: rotate after 1 year, expire after 2 years, notify 30d before expiry."
  type = object({
    expire_after         = optional(string, "P2Y")
    notify_before_expiry = optional(string, "P30D")
    automatic = optional(object({
      time_after_creation = optional(string, "P1Y")
      time_before_expiry  = optional(string)
    }), { time_after_creation = "P1Y" })
  })
  default = {}
}

###############################################################
# AKS CLUSTER
###############################################################
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version (e.g. '1.34'). null = AKS default."
  default     = null
}

variable "sku_tier" {
  type    = string
  default = "Standard"
  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "automatic_upgrade_channel" {
  type    = string
  default = "stable"
  validation {
    condition     = contains(["none", "patch", "stable", "rapid", "node-image"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be none, patch, stable, rapid, or node-image."
  }
}

variable "upgrade_override_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Passthrough to Aks: emit the upgrade_override block. Leave false for a NEW cluster (emitting it sends effectiveUntil=\"\" -> AKS rejects creation, 400 UnmarshalError). Set true ONLY on a cluster that already carries the setting (upgrade_override cannot be unset)."
}

variable "upgrade_override_force_upgrade" {
  type        = bool
  default     = false
  nullable    = false
  description = "Passthrough to Aks: upgrade_override.force_upgrade_enabled. Only effective when upgrade_override_enabled = true. Leave false except in exceptional cases."
}

variable "upgrade_override_effective_until" {
  type        = string
  default     = null
  description = "Passthrough to Aks: upgrade_override.effective_until (RFC3339). Only used when upgrade_override_enabled = true."
}

variable "node_os_upgrade_channel" {
  type    = string
  default = "SecurityPatch"
  validation {
    condition     = contains(["None", "Unmanaged", "SecurityPatch", "NodeImage"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be None, Unmanaged, SecurityPatch, or NodeImage."
  }
}

variable "private_dns_zone_id" {
  type        = string
  description = "Private DNS zone for the AKS API server. 'None' = AKS-managed (recommended for ALZ DINE)."
  default     = "None"
}

variable "private_cluster_public_fqdn_enabled" {
  type        = bool
  description = <<-EOT
  Whether AKS publishes a public FQDN that resolves to the private API
  server IP. null = auto-derive from private_dns_zone_id ('None' -> true,
  custom zone -> false). Set explicitly to false in production to hide
  the cluster's existence from public DNS queries.
  EOT
  default     = null
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Cross-sub Platform LAW resource ID — used by Microsoft Defender + AKS diagnostic settings. null = skip both (not recommended in production)."
  default     = null
}

###############################################################
# NETWORK PROFILE — Azure CNI Overlay (Microsoft default)
###############################################################
variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "172.16.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "172.16.0.10"
}

variable "outbound_type" {
  type        = string
  description = "userDefinedRouting forces traffic via the spoke RT (default route → NVA). loadBalancer creates an AKS-managed PIP."
  default     = "userDefinedRouting"
  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be 'loadBalancer', 'userDefinedRouting', or 'managedNATGateway'."
  }
}

variable "network_policy" {
  type    = string
  default = "azure"
  validation {
    condition     = contains(["azure", "calico", "cilium", "none"], var.network_policy)
    error_message = "network_policy must be azure, calico, cilium, or none."
  }
}

variable "network_data_plane" {
  type        = string
  description = <<-EOT
  Dataplane for Azure CNI Overlay: 'azure' (default) or 'cilium' (eBPF-based,
  enables Advanced Container Networking Services). Cilium dataplane requires
  network_policy = 'cilium'. Greenfield clusters can opt in for better
  performance + observability; brownfield clusters cannot switch dataplane
  in place.
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

###############################################################
# SYSTEM NODE POOL
###############################################################
variable "availability_zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "system_pool_vm_size" {
  type    = string
  default = "Standard_D4ds_v5"
}

variable "system_pool_node_count" {
  type    = number
  default = 3
}

variable "system_pool_auto_scaling" {
  type    = bool
  default = false
}

variable "system_pool_min_count" {
  type    = number
  default = 3
}

variable "system_pool_max_count" {
  type    = number
  default = 6
}

variable "system_pool_os_disk_type" {
  type    = string
  default = "Ephemeral"
  validation {
    condition     = contains(["Managed", "Ephemeral"], var.system_pool_os_disk_type)
    error_message = "system_pool_os_disk_type must be Managed or Ephemeral."
  }
}

variable "system_pool_os_disk_size_gb" {
  type    = number
  default = 100
}

variable "system_pool_host_encryption_enabled" {
  type        = bool
  description = "Encryption at host for the system pool (F-SEC-6-bis pattern). Requires CMK Disk Encryption Set on the sub or platform-managed encryption."
  default     = true
}

# NOTE: default = true matches Aks v0.2.50 secure-by-default. The `true` value prevents
# workload pods from being scheduled on the system node pool (CriticalAddonsOnly taint
# applied). Set to false for non-prod / single-pool clusters or for workloads like
# Rancher Fleet agents that don't tolerate CriticalAddonsOnly.
variable "system_pool_only_critical_addons_enabled" {
  type        = bool
  description = "Taints the system pool with CriticalAddonsOnly=true:NoSchedule to keep workloads off it. Recommended for prod multi-pool."
  default     = true
}

variable "upgrade_max_surge" {
  type    = string
  default = "33%"
}

###############################################################
# USER NODE POOLS
###############################################################
variable "user_node_pools" {
  description = <<-EOT
  Map of additional node pools (workload pools). Key = pool key (≤ 12 chars).
  Empty = system-only cluster.

  Spot pools: set priority = "Spot" (defaults to "Regular"). When Spot,
  eviction_policy and spot_max_price take effect; Azure auto-applies the
  kubernetes.azure.com/scalesetpriority=spot:NoSchedule taint, so workloads
  must add the matching toleration. Spot pools require autoscaling.
  EOT
  type = map(object({
    name                        = string
    vm_size                     = string
    os_disk_type                = optional(string, "Ephemeral")
    os_disk_size_gb             = optional(number, 100)
    host_encryption_enabled     = optional(bool, true)
    auto_scaling_enabled        = optional(bool, true)
    node_count                  = optional(number)
    min_count                   = optional(number, 1)
    max_count                   = optional(number, 3)
    zones                       = optional(list(string))
    labels                      = optional(map(string), {})
    taints                      = optional(list(string), [])
    temporary_name_for_rotation = optional(string)
    priority                    = optional(string, "Regular")
    eviction_policy             = optional(string, "Delete")
    spot_max_price              = optional(number, -1)
  }))
  default = {}
  validation {
    condition = alltrue([
      for k, v in var.user_node_pools : contains(["Regular", "Spot"], v.priority)
    ])
    error_message = "user_node_pools[*].priority must be 'Regular' or 'Spot'."
  }
  validation {
    condition = alltrue([
      for k, v in var.user_node_pools : contains(["Delete", "Deallocate"], v.eviction_policy)
    ])
    error_message = "user_node_pools[*].eviction_policy must be 'Delete' or 'Deallocate'."
  }
  validation {
    condition = alltrue([
      for k, v in var.user_node_pools : v.priority != "Spot" || v.auto_scaling_enabled
    ])
    error_message = "Spot node pools require auto_scaling_enabled = true."
  }
}

###############################################################
# CLUSTER FEATURES
###############################################################
variable "vertical_pod_autoscaler_enabled" {
  type    = bool
  default = true
}

variable "keda_enabled" {
  type    = bool
  default = false
}

variable "image_cleaner_enabled" {
  type    = bool
  default = true
}

variable "image_cleaner_interval_hours" {
  type    = number
  default = 48
}

variable "cost_analysis_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
  Enable AKS Cost Analysis (namespace-level cost breakdown in the Azure
  Portal). Free, opt-in. Requires sku_tier in ("Standard", "Premium") —
  rejected when sku_tier = "Free".
  EOT
}

variable "enable_container_insights" {
  type        = bool
  description = <<-EOT
  Enable Container Insights via the oms_agent addon (modern MSI-auth
  variant, msi_auth_for_monitoring_enabled = true). Installs the
  ama-logs DaemonSet on every node; AKS auto-creates a default DCR/DCRA
  tied to var.log_analytics_workspace_id.

  Pattern aligned with MS Learn Terraform docs
  (https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable).

  Callers typically deploy a separate ContainerInsightsCollector module
  in addition to this addon — that module installs an explicit DCR with
  custom streams (ContainerLogV2 only, skip Perf, etc.).
  EOT
  default     = true
}

variable "enable_secrets_store_csi_driver" {
  type        = bool
  description = <<-EOT
  Enable the Secrets Store CSI Driver addon (azure-keyvault-secrets-provider).
  Pattern aligned with MS Learn Terraform docs
  (https://learn.microsoft.com/azure/aks/csi-secrets-store-driver, updated
  2026-05-05).

  AKS auto-creates a UAMI in the node RG (`azurekeyvaultsecretsprovider-*`)
  — cannot opt out. RBAC on Key Vault NOT granted by AksStack; apps are
  expected to use Workload Identity per-pod (the cluster already has
  oidc_issuer + workload_identity enabled).
  EOT
  default     = false
}

variable "secrets_store_csi_driver_rotation_enabled" {
  type        = bool
  description = "Enable Secrets Store CSI Driver auto-rotation. Default true (MS recommended)."
  default     = true
}

variable "secrets_store_csi_driver_rotation_interval" {
  type        = string
  description = "Secret rotation polling interval. MS default 2m."
  default     = "2m"
}

variable "enable_web_app_routing" {
  type        = bool
  description = <<-EOT
  Enable the AKS Application Routing addon (managed nginx ingress).
  Modern AKS-native ingress; supports both internal (private LB) and
  external (Internet) via web_app_routing_default_nginx_controller or
  per-Ingress annotation.
  EOT
  default     = false
}

variable "web_app_routing_dns_zone_ids" {
  type        = list(string)
  description = "Azure DNS zone IDs to integrate (BYO-DNS). Empty list = no DNS integration."
  default     = []
}

variable "web_app_routing_default_nginx_controller" {
  type        = string
  description = "Default ingress controller mode: None | Internal | External | AnnotationControlled. null = AnnotationControlled (azurerm default)."
  default     = null
}

variable "maintenance_window" {
  description = "AKS upgrade maintenance window. day = day-of-week, hour_start/end in UTC."
  type = object({
    day        = string
    hour_start = number
    hour_end   = number
  })
  default = null
}

###############################################################
# RBAC ROLE ASSIGNMENTS
###############################################################
variable "cluster_admin_principal_ids" {
  type        = list(string)
  description = "Object IDs granted Azure Kubernetes Service RBAC Cluster Admin on this cluster (PIM-eligible group in prod, RBAC permanent in nprd)."
  default     = []
}

variable "cluster_user_principal_ids" {
  type        = list(string)
  description = "Object IDs granted Azure Kubernetes Service Cluster User Role (kubectl exec/logs scope, no admin)."
  default     = []
}

variable "acr_pull_target_ids" {
  type        = list(string)
  description = "Container Registry resource IDs where the kubelet UAMI should get AcrPull (image pull). Empty = no ACR wired."
  default     = []
}

###############################################################
# AKS SUPPORT PLAN
###############################################################
variable "support_plan" {
  description = "AKS support plan. 'KubernetesOfficial' = standard 12-month support window. 'AKSLongTermSupport' = 30-month LTS support window (Premium SKU only)."
  type        = string
  default     = "KubernetesOfficial"
  nullable    = false
  validation {
    condition     = contains(["KubernetesOfficial", "AKSLongTermSupport"], var.support_plan)
    error_message = "support_plan must be 'KubernetesOfficial' or 'AKSLongTermSupport'."
  }
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the AKS cluster (propagated to ../Aks). Production clusters should use CanNotDelete. Set to null to skip."
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
# TAGS
###############################################################
variable "tags" {
  type     = map(string)
  default  = {}
  nullable = false
}
