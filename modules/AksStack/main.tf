###############################################################
# MODULE: AksStack — Main (wrapper-style orchestrator)
#
# Composes a full AKS workload bundle. Child modules are sourced
# via relative paths (../Sibling). Single source of truth for
# each child resource — fixes to KeyVault, ManagedIdentity, Aks,
# etc. propagate to AksStack at the next release bump.
###############################################################

resource "time_static" "time" {}

data "azurerm_client_config" "current" {}

###############################################################
# Naming
###############################################################
locals {
  prefix = "${var.subscription_acronym}-${var.environment}-${var.region_code}"

  # KV name reused throughout (24-char limit policed by KeyVault module)
  kv_name_base = "kv-${local.prefix}-${var.kv_workload}"
  kv_name      = var.kv_suffix != null ? "${local.kv_name_base}-${var.kv_suffix}" : local.kv_name_base

  effective_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# STATE MIGRATION: module.rg (ResourceGroup child module) removed in v0.2.66.
# The RG is intentionally NOT destroyed — it is now caller-managed.
# Callers must run: terraform state rm 'module.aks_stack.module.rg[0]'
# and ensure var.resource_group_name points at the pre-existing RG.
###############################################################
removed {
  from = module.rg

  lifecycle {
    destroy = false
  }
}

locals {
  # Optional dedicated RG for KV + KV PE + KV Key (separation of duties).
  # When null, falls back to the cluster RG (single-RG mode).
  effective_kv_rg_name = var.kv_resource_group_name != null ? var.kv_resource_group_name : var.resource_group_name
}

###############################################################
# Control Plane User Assigned Identity
###############################################################
module "id_cp" {
  source = "../ManagedIdentity"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = "aks-cp"
  location             = var.location
  resource_group_name  = var.resource_group_name

  tags = local.effective_tags
}

###############################################################
# Kubelet User Assigned Identity
###############################################################
module "id_kubelet" {
  source = "../ManagedIdentity"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = "aks-kubelet"
  location             = var.location
  resource_group_name  = var.resource_group_name

  tags = local.effective_tags
}

###############################################################
# Key Vault — etcd CMK + workload secrets
#
# Premium SKU (HSM-backed keys), RBAC-only, public access disabled.
# `assign_rbac_to_current_user = true` adds the deployer SP for the
# initial key creation; `role_assignments` adds caller-provided
# admins (typically a PIM/RBAC group per the entra-id-rbac convention).
###############################################################
module "kv" {
  source = "../KeyVault"

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.kv_workload
  # KV name follows the canonical {prefix}-{workload}; kv_suffix is
  # not exposed by KeyVault module — caller must shorten workload
  # if the computed name exceeds 24 chars.
  location            = var.location
  resource_group_name = local.effective_kv_rg_name
  tenant_id           = var.tenant_id

  sku_name                      = var.kv_sku_name
  enable_rbac                   = true
  assign_rbac_to_current_user   = true
  enabled_for_disk_encryption   = true
  soft_delete_retention_days    = var.kv_soft_delete_retention_days
  purge_protection_enabled      = true
  public_network_access_enabled = false

  role_assignments = {
    for idx, pid in var.kv_admin_principal_ids : "admin-${idx}" => {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = pid
    }
  }

  tags = local.effective_tags
}

###############################################################
# Key Vault Private Endpoint
#
# Mandatory in this LZ — KV is deployed with public_network_access_enabled
# = false, so anything that needs to talk to the KV (AKS control plane for
# KMS v2, pods via SDK or Secrets Store CSI) requires a PE.
#
# subresource = "vault". privateDnsZoneGroup created by ALZ DINE Policy
# (privatelink.vaultcore.azure.net zone in connectivity sub) — module's
# baked-in `lifecycle ignore_changes [private_dns_zone_group]` keeps Policy
# and Terraform from fighting.
###############################################################
module "kv_pe" {
  source = "../PrivateEndpoint"

  location            = var.location
  resource_group_name = local.effective_kv_rg_name
  subnet_id           = var.kv_pe_subnet_id

  private_endpoints = {
    kv = {
      name              = "pep-${local.prefix}-${var.kv_workload}-001"
      resource_id       = module.kv.id
      subresource_names = ["vault"]
    }
  }

  tags = local.effective_tags
}

###############################################################
# DNS propagation wait (ALZ DINE Policy)
#
# After the KV PE is created, ALZ DINE Policy deploys the
# privateDnsZoneGroup (privatelink.vaultcore.azure.net A record).
# Propagation typically takes 1-5 min. The AKS create call attaches
# the etcd CMK via KMS Private and resolves the KV through this DNS,
# so we sleep before triggering the cluster create to avoid the race.
#
# Only fires on initial PE creation. Configurable via
# var.kv_pe_dns_propagation_wait (default 5m, set "0s" to skip).
###############################################################
resource "time_sleep" "wait_for_dine_dns" {
  depends_on      = [module.kv_pe]
  create_duration = var.kv_pe_dns_propagation_wait

  triggers = {
    pe_id = module.kv_pe.ids["kv"]
  }
}

###############################################################
# Key Vault Key — etcd CMK (KMS v2)
#
# RSA 2048, full key_opts for KMS, automatic rotation.
# depends_on the KV module to wait for the deployer's KV Admin
# role assignment to propagate before the key creation API call.
###############################################################
module "etcd_key" {
  source = "../KeyVault-Key"

  keys = {
    etcd = {
      name         = "aks-etcd-key"
      key_vault_id = module.kv.id
      key_type     = "RSA"
      key_size     = 2048
      key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]

      rotation_policy = {
        expire_after         = var.etcd_key_rotation_policy.expire_after
        notify_before_expiry = var.etcd_key_rotation_policy.notify_before_expiry
        automatic = {
          time_after_creation = var.etcd_key_rotation_policy.automatic.time_after_creation
          time_before_expiry  = var.etcd_key_rotation_policy.automatic.time_before_expiry
        }
      }

      tags = local.effective_tags
    }
  }

  depends_on = [
    module.kv,
  ]
}

###############################################################
# AKS Cluster
#
# All Microsoft AKS best-practice defaults baked in by the Aks
# module. AksStack just routes inputs.
###############################################################
module "aks" {
  source = "../Aks"

  subscription_acronym     = var.subscription_acronym
  environment              = var.environment
  region_code              = var.region_code
  workload                 = var.workload
  location                 = var.location
  resource_group_name      = var.resource_group_name
  node_resource_group_name = var.node_resource_group_name

  tenant_id = var.tenant_id

  # Identities (from this stack's UAMIs)
  cluster_identity_id        = module.id_cp.id
  kubelet_identity_id        = module.id_kubelet.id
  kubelet_identity_client_id = module.id_kubelet.client_id
  kubelet_identity_object_id = module.id_kubelet.principal_id

  # Network
  node_subnet_id       = var.node_subnet_id
  api_server_subnet_id = var.api_server_subnet_id

  # Cluster config
  kubernetes_version                  = var.kubernetes_version
  sku_tier                            = var.sku_tier
  support_plan                        = var.support_plan
  automatic_upgrade_channel           = var.automatic_upgrade_channel
  node_os_upgrade_channel             = var.node_os_upgrade_channel
  upgrade_override_enabled            = var.upgrade_override_enabled
  upgrade_override_force_upgrade      = var.upgrade_override_force_upgrade
  upgrade_override_effective_until    = var.upgrade_override_effective_until
  private_dns_zone_id                 = var.private_dns_zone_id
  private_cluster_public_fqdn_enabled = var.private_cluster_public_fqdn_enabled

  # KMS v2 — gated by kms_v2_enabled.
  # - false (default): cluster deploys without KMS, etcd CMK still created
  #   for later activation via `az aks update`.
  # - true + api_server_subnet_id == null: inline KMS block fires (Aks
  #   module gate), requires KV Private reachability (PE on KV).
  # - true + api_server_subnet_id != null: inline block stays empty, KMS
  #   must be activated post-deploy via `az aks update`.
  #
  # Note: azurerm requires a VERSIONED key_vault_key_id (with GUID suffix).
  # Auto-rotation drift is suppressed by the Aks module's lifecycle
  # ignore_changes [key_management_service]. The versionless id stays
  # exposed via the post_deploy_az_cli_commands output for the CLI fallback
  # (`az aks update --azure-keyvault-kms-key-id` accepts both).
  kms_key_id       = var.kms_v2_enabled ? module.etcd_key.ids["etcd"] : null
  kms_key_vault_id = var.kms_v2_enabled ? module.kv.id : null

  # Network profile (CNI Overlay defaults)
  network_policy     = var.network_policy
  network_data_plane = var.network_data_plane
  pod_cidr           = var.pod_cidr
  service_cidr       = var.service_cidr
  dns_service_ip     = var.dns_service_ip
  outbound_type      = var.outbound_type

  # System pool
  system_pool_vm_size                      = var.system_pool_vm_size
  system_pool_node_count                   = var.system_pool_node_count
  system_pool_auto_scaling                 = var.system_pool_auto_scaling
  system_pool_min_count                    = var.system_pool_min_count
  system_pool_max_count                    = var.system_pool_max_count
  system_pool_os_disk_type                 = var.system_pool_os_disk_type
  system_pool_os_disk_size_gb              = var.system_pool_os_disk_size_gb
  system_pool_host_encryption_enabled      = var.system_pool_host_encryption_enabled
  system_pool_only_critical_addons_enabled = var.system_pool_only_critical_addons_enabled
  availability_zones                       = var.availability_zones
  upgrade_max_surge                        = var.upgrade_max_surge

  # User node pools
  user_node_pools = var.user_node_pools

  # Cluster features
  vertical_pod_autoscaler_enabled = var.vertical_pod_autoscaler_enabled
  keda_enabled                    = var.keda_enabled
  image_cleaner_enabled           = var.image_cleaner_enabled
  image_cleaner_interval_hours    = var.image_cleaner_interval_hours
  cost_analysis_enabled           = var.cost_analysis_enabled

  # Maintenance
  maintenance_window = var.maintenance_window

  # Monitoring
  # Container Insights (ama-logs agent via oms_agent block, MSI auth).
  # The expected ALZ DINE policy that would have auto-deployed this never
  # materialised in our LZ — wired explicitly here. AKS auto-creates a
  # default DCR/DCRA when the addon is enabled; callers typically also
  # deploy a ContainerInsightsCollector module to add custom streams.
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enable_container_insights  = var.enable_container_insights

  # Secrets Store CSI Driver (azure-keyvault-secrets-provider addon).
  # Apps consume KV secrets via SecretProviderClass + Workload Identity
  # (per-pod), not the auto-created cluster-wide UAMI.
  enable_secrets_store_csi_driver            = var.enable_secrets_store_csi_driver
  secrets_store_csi_driver_rotation_enabled  = var.secrets_store_csi_driver_rotation_enabled
  secrets_store_csi_driver_rotation_interval = var.secrets_store_csi_driver_rotation_interval

  # Application Routing addon (managed nginx ingress). Modern AKS-native
  # ingress; supports both internal (private LB) and external (Internet).
  enable_web_app_routing                   = var.enable_web_app_routing
  web_app_routing_dns_zone_ids             = var.web_app_routing_dns_zone_ids
  web_app_routing_default_nginx_controller = var.web_app_routing_default_nginx_controller

  tags = local.effective_tags
  lock = var.lock

  # Sequenced creation order:
  # - cp_subnet_network_contrib: required for AKS to attach to the node subnet
  # - cp_apiserver_subnet_network_contrib: required for VNet integration
  #   (joinLoadBalancer/action on the apiserver subnet, see rbac.tf)
  # - cp_kubelet_mi_operator: required for AKS to assign the kubelet UAMI to
  #   VMSS instances (CustomKubeletIdentityMissingPermissionError otherwise)
  # - cp_kv_contributor: required for AKS to approve its auto-created PE
  #   connection on the KV when KMS Private fires (LinkedAuthorizationFailed
  #   on PrivateEndpointConnectionsApproval/action otherwise)
  # - cp_kv_crypto_user: required for the CP identity to Wrap/Unwrap on the
  #   etcd CMK in KMS Private mode (kms-plugin runs as cluster identity in
  #   private mode, not kubelet — see rbac.tf RBAC #1d)
  # - module.kv_pe: PE on the etcd CMK KV (network path)
  # - time_sleep.wait_for_dine_dns: ALZ DINE Policy DNS group propagation
  #   delay — the AKS create call resolves the KV via privatelink.vaultcore
  #   when KMS attaches; without this wait, the first apply often fails with
  #   a KMS-unreachable error.
  depends_on = [
    module.cp_subnet_network_contrib,
    module.cp_apiserver_subnet_network_contrib,
    module.cp_kubelet_mi_operator,
    module.cp_kv_contributor,
    module.cp_kv_crypto_user,
    module.kv_pe,
    time_sleep.wait_for_dine_dns,
  ]
}

###############################################################
# Diagnostic Settings
#
# Owned by the wrapped Aks module, which auto-creates
# azurerm_monitor_diagnostic_setting.this[0] whenever
# log_analytics_workspace_id is set. AksStack does NOT add a
# second one — duplicating same-name same-target diag settings
# causes an Azure conflict at apply time.
###############################################################
