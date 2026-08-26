###############################################################
# MODULE: Aks - Main
# Description: Azure Kubernetes Service - Private Cluster
#              Azure CNI Overlay, KMS v2, Defender, OIDC/WI
###############################################################

data "azurerm_client_config" "current" {}

resource "time_static" "time" {}

###############################################################
# Naming Convention
# Convention: aks-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    aks-api-prod-gwc-apim
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name         = var.name != null ? var.name : module.naming["this"].result.kubernetes_cluster.name
  node_rg_name = var.node_resource_group_name != null ? var.node_resource_group_name : "rg-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}-nodes"
  dns_prefix   = var.dns_prefix != null ? var.dns_prefix : replace(local.name, "-", "")
}

###############################################################
# RESOURCE: AKS Cluster
###############################################################
resource "azurerm_kubernetes_cluster" "this" {
  # checkov:skip=CKV_AZURE_117: CMK disk encryption is wired via the optional
  # var.disk_encryption_set_id. A Disk Encryption Set is a customer-managed
  # external dependency (Key Vault + key + DES + RBAC) that this module does not
  # fabricate; when the caller supplies the DES ID it IS applied below. The skip
  # documents that a null default (platform-managed keys) is an accepted posture
  # for consumers who have not provisioned a DES — it is not a silenced misconfig.
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  support_plan        = var.support_plan
  node_resource_group = local.node_rg_name

  # ─── Customer-Managed Disk Encryption (CKV_AZURE_117) ────────
  # CMK encryption of node OS + data disks via a customer-managed Disk
  # Encryption Set. Null = Azure platform-managed keys. ForceNew: OS-disk CMK
  # can only be set at cluster creation (MS Learn: azure-disk-customer-managed-keys).
  disk_encryption_set_id = var.disk_encryption_set_id

  # ─── Private Cluster ─────────────────────────────────────────
  private_cluster_enabled = true
  private_dns_zone_id     = var.private_dns_zone_id
  # Public FQDN resolution: explicit override > auto-compute from DNS zone
  private_cluster_public_fqdn_enabled = var.private_cluster_public_fqdn_enabled != null ? var.private_cluster_public_fqdn_enabled : (var.private_dns_zone_id == "None")

  # ─── Identity (UserAssigned) ─────────────────────────────────
  identity {
    type         = "UserAssigned"
    identity_ids = [var.cluster_identity_id]
  }

  kubelet_identity {
    client_id                 = var.kubelet_identity_client_id
    object_id                 = var.kubelet_identity_object_id
    user_assigned_identity_id = var.kubelet_identity_id
  }

  # ─── Network Profile - Azure CNI Overlay ─────────────────────
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = var.network_policy
    network_data_plane  = var.network_data_plane
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = var.outbound_type
  }

  # ─── Default Node Pool (System) ─────────────────────────────
  default_node_pool {
    # checkov:skip=CKV_AZURE_227: host encryption is exposed via var.system_pool_host_encryption_enabled (and per additional pool); kept opt-in / default false because enabling requires Microsoft.Compute/EncryptionAtHost registered on the subscription + supported VM sizes/regions, else AKS creation fails.
    name                         = "system"
    vm_size                      = var.system_pool_vm_size
    node_count                   = var.system_pool_auto_scaling ? null : var.system_pool_node_count
    min_count                    = var.system_pool_auto_scaling ? var.system_pool_min_count : null
    max_count                    = var.system_pool_auto_scaling ? var.system_pool_max_count : null
    auto_scaling_enabled         = var.system_pool_auto_scaling
    os_disk_type                 = var.system_pool_os_disk_type
    os_disk_size_gb              = var.system_pool_os_disk_size_gb
    host_encryption_enabled      = var.system_pool_host_encryption_enabled
    vnet_subnet_id               = var.node_subnet_id
    zones                        = var.availability_zones
    only_critical_addons_enabled = var.system_pool_only_critical_addons_enabled
    temporary_name_for_rotation  = "tmpsys"
    # F-14: tags on default_node_pool. ROTATION WARNING: adding/changing tags
    # on an existing default_node_pool triggers a full node pool rotation
    # (surge + drain + replace). The lifecycle ignore_changes below suppresses
    # drift detection on this field for existing clusters. Set desired tags
    # BEFORE first apply on new clusters; after that, tag changes require a
    # planned rotation window.
    tags = merge(var.tags, { NodePool = "system" })

    upgrade_settings {
      max_surge = var.upgrade_max_surge
    }
  }

  # ─── KMS v2 - Azure Key Vault Encryption ────────────────────
  # When api_server_subnet_id is set, KMS is managed via azapi (see below)
  dynamic "key_management_service" {
    for_each = var.kms_key_id != null && var.api_server_subnet_id == null ? [1] : []
    content {
      key_vault_key_id         = var.kms_key_id
      key_vault_network_access = "Private"
    }
  }

  # ─── Local account hardening ────────────────────────────────
  # Disables the built-in Kubernetes local admin account.
  # AAD RBAC (below) is the ONLY auth path — no kubectl bypass via
  # local kubeconfig. CAF secure baseline + MS AKS hardening guide.
  # BREAKING (v0.2.50): existing kubeconfigs obtained via
  # `az aks get-credentials --admin` will stop working. Use
  # `az aks get-credentials` (Entra ID flow) instead.
  local_account_disabled = true

  # ─── Azure AD RBAC ──────────────────────────────────────────
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = var.tenant_id
  }

  # ─── OIDC + Workload Identity ──────────────────────────────
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ─── Microsoft Defender ────────────────────────────────────
  dynamic "microsoft_defender" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  # ─── Managed Prometheus (ama-metrics agent) ───────────────
  # F-4: dynamic block — null = omit entirely; {} = enable with no label filter.
  # Restrict annotations_allowed / labels_allowed to avoid high-cardinality label
  # explosion on large clusters. See var.monitor_metrics description.
  dynamic "monitor_metrics" {
    for_each = var.monitor_metrics != null ? [var.monitor_metrics] : []
    content {
      annotations_allowed = monitor_metrics.value.annotations_allowed
      labels_allowed      = monitor_metrics.value.labels_allowed
    }
  }

  # ─── Container Insights (ama-logs agent) — modern MSI auth ───
  # Pattern aligned with MS Learn (kubernetes-monitoring-enable.md,
  # updated 2026-04-17, "Terraform" tab). `msi_auth_for_monitoring_enabled`
  # opts the addon into Azure Monitor Agent (AMA) under the hood — the
  # legacy Log Analytics shared-key auth path is gone.
  dynamic "oms_agent" {
    for_each = var.enable_container_insights ? [1] : []
    content {
      log_analytics_workspace_id      = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  # ─── Secrets Store CSI Driver (azure-keyvault-secrets-provider) ──
  # Pattern aligned with MS Learn (csi-secrets-store-driver.md, "Terraform"
  # tab, updated 2026-05-05). Enables the addon and installs the
  # secrets-store-csi-driver + secrets-store-provider-azure DaemonSets.
  #
  # AKS auto-creates a UAMI `azurekeyvaultsecretsprovider-<cluster>` in
  # the node RG (cannot opt out). RBAC on Key Vault NOT granted by this
  # module — apps are expected to use Workload Identity per-pod, which
  # the cluster supports via oidc_issuer_enabled + workload_identity_enabled.
  dynamic "key_vault_secrets_provider" {
    for_each = var.enable_secrets_store_csi_driver ? [1] : []
    content {
      secret_rotation_enabled  = var.secrets_store_csi_driver_rotation_enabled
      secret_rotation_interval = var.secrets_store_csi_driver_rotation_interval
    }
  }

  # ─── Application Routing addon (managed nginx ingress) ───────
  # Modern AKS-native ingress (replaces AGIC). Installs nginx-ingress-
  # controller in app-routing-system namespace + the IngressClass
  # `webapprouting.kubernetes.azure.com`. Supports both internal (private
  # LB in the cluster VNet) and external (Internet) via the
  # default_nginx_controller knob, or per-Ingress annotation.
  #
  # Complementary to AGC: AGC handles public-only ingress (Internet-
  # facing); Application Routing covers internal/private + AGC's
  # public-only gap (admin UIs, internal services).
  dynamic "web_app_routing" {
    for_each = var.enable_web_app_routing ? [1] : []
    content {
      dns_zone_ids             = var.web_app_routing_dns_zone_ids
      default_nginx_controller = var.web_app_routing_default_nginx_controller
    }
  }

  # ─── Workload Autoscaler Profile (VPA + KEDA) ──────────────
  # Enables the VPA addon (recommender, updater, admission-controller).
  # Per-workload mode (Off/Initial/Auto) configured via VerticalPodAutoscaler
  # CRDs in Kubernetes — NOT at cluster level. Default usage: create VPA
  # objects with updateMode=Off for recommend-only, safe dry-run.
  workload_autoscaler_profile {
    vertical_pod_autoscaler_enabled = var.vertical_pod_autoscaler_enabled
    keda_enabled                    = var.keda_enabled
  }

  # ─── Azure Policy Add-on ──────────────────────────────────
  azure_policy_enabled = true

  # ─── Auto Upgrade ─────────────────────────────────────────
  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  # ─── Upgrade Override ─────────────────────────────────────
  # TWO opposing traps — DO NOT hardcode this block either way:
  #
  #   1. Cannot be UNSET once posted: after Azure sets
  #      upgradeSettings.overrideSettings (e.g. a force/auto upgrade on a
  #      deprecation), the AKS API refuses to remove it — an undeclared block
  #      makes the provider attempt an unset and fail: "`upgrade_override`
  #      cannot be unset" (per azurerm docs). Such clusters MUST keep emitting
  #      the block → set upgrade_override_enabled = true.
  #
  #   2. Cannot be CREATED with it on a greenfield cluster: when the block is
  #      emitted, azurerm sends effectiveUntil: "" (empty) at the initial
  #      CreateOrUpdate, which the API rejects: 400 UnmarshalError, parsing
  #      time "" ... cannot parse "" as "2006". So a NEW cluster must NOT emit
  #      the block → keep upgrade_override_enabled = false (the default).
  #
  # Hence the block is CONDITIONAL: default false so greenfield clusters
  # create; existing clusters that already carry the setting flip it to true.
  # effective_until is exposed (RFC3339) because the API requires a real date
  # whenever a force upgrade is actually scheduled (the empty string is what
  # broke creation).
  dynamic "upgrade_override" {
    for_each = var.upgrade_override_enabled ? [1] : []
    content {
      force_upgrade_enabled = var.upgrade_override_force_upgrade
      effective_until       = var.upgrade_override_effective_until
    }
  }

  # ─── Image Cleaner ──────────────────────────────────────
  image_cleaner_enabled        = var.image_cleaner_enabled
  image_cleaner_interval_hours = var.image_cleaner_enabled ? var.image_cleaner_interval_hours : null

  # ─── Cost Analysis ──────────────────────────────────────
  # Namespace-level cost breakdown in Azure Portal. Free, opt-in.
  # Requires sku_tier in ("Standard", "Premium") — Free is rejected by ARM.
  cost_analysis_enabled = var.cost_analysis_enabled

  # ─── Maintenance Window ─────────────────────────────────
  dynamic "maintenance_window" {
    for_each = var.maintenance_window != null ? [var.maintenance_window] : []
    content {
      allowed {
        day   = maintenance_window.value.day
        hours = range(maintenance_window.value.hour_start, maintenance_window.value.hour_end)
      }
    }
  }

  # ─── Tags ──────────────────────────────────────────────────
  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = var.support_plan != "AKSLongTermSupport" || var.sku_tier == "Premium"
      error_message = "AKSLongTermSupport requires sku_tier = 'Premium'."
    }

    ignore_changes = [
      kubernetes_version,
      # F-14: default_node_pool.tags are ignored to prevent rotation on
      # existing clusters. Tags must be set before first apply.
      default_node_pool[0].tags,
      # F-5: node_count is NO LONGER ignored unconditionally. When the cluster
      # autoscaler is active (system_pool_auto_scaling = true), the autoscaler
      # mutates node_count out-of-band — Terraform will detect drift on next
      # plan. Callers using autoscaling must accept this drift or set
      # node_count = null in their state via `terraform state rm` after the
      # first apply, OR suppress it with a targeted lifecycle ignore in their
      # root module. Terraform does not support conditional ignore_changes so
      # an unconditional ignore was the only alternative; that silently
      # discards deliberate scale changes when autoscaling is OFF — which is
      # worse than the drift signal when autoscaling is ON.
      # api_server_access_profile and key_management_service are managed
      # via azapi_update_resource post-create (azurerm v4 limitation)
      api_server_access_profile,
      key_management_service,
      # upgrade_override: the overrideSettings (force-upgrade) block can be set
      # OUT-OF-BAND (az aks update --enable-force-upgrade / --upgrade-override-until,
      # or inherited). azurerm refreshes it into state; since the module does not
      # emit the block by default (it is conditional), the plan would try to
      # REMOVE it — which azurerm cannot do ("`upgrade_override` cannot be unset",
      # provider limitation: modifiable, never removable). Ignoring its drift is
      # the module-only, consumer-transparent fix (force-upgrade is a one-off
      # ops action via az; not managed in IaC), consistent with the other
      # out-of-band-mutated fields above.
      upgrade_override,
      # ALZ policy was expected to modify microsoft_defender casing
      # (the policy doesn't exist in our LZ as of 2026-05-13, but the
      # ignore is kept defensively in case it gets assigned later).
      # oms_agent is NO LONGER ignored — it is now an explicit, caller-
      # gated block (see enable_container_insights variable). The
      # previously assumed ALZ DINE for omsagent does not exist in this LZ.
      microsoft_defender,
    ]
  }
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_kubernetes_cluster.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: User Node Pools
###############################################################
resource "azurerm_kubernetes_cluster_node_pool" "this" {
  # checkov:skip=CKV_AZURE_227: host encryption is exposed per pool via user_node_pools[*].host_encryption_enabled; kept opt-in / default false because enabling requires Microsoft.Compute/EncryptionAtHost registered on the subscription + supported VM sizes/regions, else node pool creation fails.
  for_each = var.user_node_pools

  name                        = each.value.name
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  vm_size                     = each.value.vm_size
  os_disk_type                = each.value.os_disk_type
  os_disk_size_gb             = each.value.os_disk_size_gb
  host_encryption_enabled     = each.value.host_encryption_enabled
  vnet_subnet_id              = var.node_subnet_id
  zones                       = coalesce(each.value.zones, var.availability_zones)
  auto_scaling_enabled        = each.value.auto_scaling_enabled
  min_count                   = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count                   = each.value.auto_scaling_enabled ? each.value.max_count : null
  node_count                  = each.value.auto_scaling_enabled ? null : coalesce(each.value.node_count, each.value.min_count)
  node_labels                 = each.value.labels
  node_taints                 = each.value.taints
  temporary_name_for_rotation = coalesce(each.value.temporary_name_for_rotation, "${substr(each.value.name, 0, 9)}tmp")

  # Spot pool support — Regular by default, Spot opts in via priority="Spot".
  # Azure auto-applies the kubernetes.azure.com/scalesetpriority=spot:NoSchedule
  # taint to spot pools, but workload-specific tolerations are still required.
  priority        = each.value.priority
  eviction_policy = each.value.priority == "Spot" ? each.value.eviction_policy : null
  spot_max_price  = each.value.priority == "Spot" ? each.value.spot_max_price : null

  upgrade_settings {
    max_surge = var.upgrade_max_surge
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
      NodePool  = each.value.name
    }
  )

  lifecycle {
    # F-15: node_count ignore_changes removed — same rationale as F-5 on the
    # system pool. Unconditional ignore silently discards deliberate scale
    # changes when auto_scaling_enabled = false. Callers using autoscaling
    # will see drift on node_count; suppress it caller-side if desired.
  }
}

###############################################################
# Container Insights — managed by ALZ DINE Policy
# The policy automatically creates a DCR (MSCI-{region}-{cluster})
# and the ContainerInsightsExtension association on each AKS cluster.
# Do not manage here to avoid Terraform vs Policy conflicts.
###############################################################

###############################################################
# RESOURCE: Diagnostic Settings
###############################################################
resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${local.name}"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }
}

###############################################################
# RESOURCE: Bootstrap — VNet Integration + KMS Private (via az CLI)
# ─────────────────────────────────────────────────────────────
# azurerm v4 cannot create a cluster with apiServerAccessProfile
# or KMS Private inline.
#
# Why null_resource + local-exec, NOT azapi_update_resource:
#   azapi_update_resource was tried (commit b3e11df) but has a merge
#   bug specific to AKS managedClusters: the GET+merge+PUT silently
#   drops apiServerAccessProfile. azapi reports "Creation complete"
#   yet `az aks show` returns enableVnetIntegration=null. The KMS
#   PATCH then fails with HTTP 400 "Vnet integration should be
#   enabled when KeyVault network access is Private". Verified via
#   Azure MCP after azapi "success" — the field really wasn't
#   persisted. Until the azapi provider fixes the merge for
#   managedClusters PUT, the canonical AKS pattern from MS docs is
#   `az aks update`.
#
# Order:
#   1. cluster created without VNet integration / KMS
#   2. enable_vnet_integration       (`az aks update --enable-apiserver-vnet-integration`)
#   3. restart_after_vnet_integration (`az aks stop` + `az aks start`)
#   4. enable_kms                    (`az aks update --enable-azure-keyvault-kms`)
#
# All 3 steps are skipped when the corresponding inputs are null.
#
# Pre-requisites on the Terraform runner:
#   - `az` CLI installed
#   - PowerShell 7+ (pwsh) on PATH — cross-platform, so these run on both
#     Windows and Linux pipeline agents (interpreter = "pwsh")
#   - ARM_CLIENT_ID + ARM_TENANT_ID, plus EITHER ARM_CLIENT_SECRET
#     (classic SPN) OR ARM_OIDC_TOKEN (Workload Identity Federation / OIDC
#     pipelines). The shared login helper (locals below) picks the right mode.
###############################################################

locals {
  # Interpreter for the 3 post-create local-exec provisioners. `pwsh`
  # (PowerShell 7+, cross-platform) NOT `powershell` (Windows-only) so the
  # provisioners run on both Windows and Linux pipeline agents (e.g. the
  # Ubuntu Managed DevOps Pool agents used downstream). pwsh runs the scripts
  # unchanged (Write-Host / $env: / [System.IO.Path] / [System.Guid] / throw
  # are all supported in PowerShell Core).
  local_exec_interpreter = ["pwsh", "-NoProfile", "-Command"]

  # Shared `az login` preamble for the 3 post-create local-exec provisioners.
  # Supports BOTH classic SPN secret auth AND Workload Identity Federation:
  # when ARM_OIDC_TOKEN is set (federated pipeline / ARM_USE_OIDC=true) it logs
  # in with --federated-token, else it falls back to --password
  # (ARM_CLIENT_SECRET). Requires az CLI >= 2.30 for --federated-token.
  # Factored here so the 3 provisioners can never diverge. Opens a `try {` that
  # each provisioner's work continues; local.az_login_cleanup closes it.
  az_federated_login = <<-PS
    $ErrorActionPreference = "Stop"
    if (-not $env:ARM_CLIENT_ID -or -not $env:ARM_TENANT_ID -or (-not $env:ARM_CLIENT_SECRET -and -not $env:ARM_OIDC_TOKEN)) {
      throw "ARM_CLIENT_ID + ARM_TENANT_ID + (ARM_CLIENT_SECRET or ARM_OIDC_TOKEN) must be set."
    }
    $azDir = Join-Path ([System.IO.Path]::GetTempPath()) ("az-tf-" + [System.Guid]::NewGuid().ToString())
    $env:AZURE_CONFIG_DIR = $azDir
    try {
      if ($env:ARM_OIDC_TOKEN) {
        az login --service-principal --username $env:ARM_CLIENT_ID --tenant $env:ARM_TENANT_ID --federated-token $env:ARM_OIDC_TOKEN --only-show-errors | Out-Null
      } else {
        az login --service-principal --username $env:ARM_CLIENT_ID --password $env:ARM_CLIENT_SECRET --tenant $env:ARM_TENANT_ID --only-show-errors | Out-Null
      }
      if ($LASTEXITCODE -ne 0) { throw "az login failed (exit $LASTEXITCODE)" }
  PS

  # Closes the try{} from az_federated_login, removes the scoped az config dir,
  # and forces a clean exit (az can leave $LASTEXITCODE non-zero despite success).
  az_login_cleanup = <<-PS
      } finally {
        Remove-Item -Recurse -Force $azDir -ErrorAction SilentlyContinue
      }
      $global:LASTEXITCODE = 0
      exit 0
  PS
}

resource "null_resource" "enable_vnet_integration" {
  count = var.api_server_subnet_id != null ? 1 : 0

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.this.id
    subnet_id  = var.api_server_subnet_id
  }

  provisioner "local-exec" {
    interpreter = local.local_exec_interpreter
    command     = <<-EOT
      ${local.az_federated_login}

        # Idempotency: skip the update only when BOTH:
        #   - VNet integration is already enabled
        #   - Cluster is in a healthy provisioningState (Succeeded)
        # Otherwise, re-run to recover from a Failed state.
        $currentVnet = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "apiServerAccessProfile.enableVnetIntegration" -o tsv 2>$null
        $currentState = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "provisioningState" -o tsv 2>$null
        if ($currentVnet -eq "true" -and $currentState -eq "Succeeded") {
          Write-Host "VNet integration already enabled and cluster healthy - skipping az aks update."
        } else {
          Write-Host "Enabling/recovering API Server VNet Integration (vnet=$currentVnet, state=$currentState, ~3-5 min)..."
          az aks update --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --enable-apiserver-vnet-integration --apiserver-subnet-id ${var.api_server_subnet_id} --yes --output none
        }

        # Verify state really changed (resilient to flaky exit codes).
        $verified = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "apiServerAccessProfile.enableVnetIntegration" -o tsv
        if ($verified -ne "true") { throw "VNet integration state verification failed (got: '$verified', expected 'true')" }
        Write-Host "VNet integration confirmed enabled."
      ${local.az_login_cleanup}
    EOT
  }

  depends_on = [
    azurerm_kubernetes_cluster.this,
    azurerm_kubernetes_cluster_node_pool.this,
  ]
}

# Cluster restart required by Azure after enabling VNet integration.
# Per MS docs (https://learn.microsoft.com/azure/aks/api-server-vnet-integration):
#
#   "Manual restart required. After enabling API Server VNet Integration,
#    due to control plane resource transition, you must immediately restart
#    the cluster for the change to take effect. This restart is not automated.
#    Delaying the restart increases the risk of capacity becoming unavailable."
#
# stop/start are POST actions on the ARM resource (not PATCH semantics) so
# azapi_update_resource is not the right fit — kept as null_resource.
# Pre-requisites on the Terraform runner: see the shared login helper
# (locals.az_federated_login) — ARM_CLIENT_ID + ARM_TENANT_ID plus either
# ARM_CLIENT_SECRET or ARM_OIDC_TOKEN (WIF/OIDC). `az` CLI + PowerShell required.
resource "null_resource" "restart_after_vnet_integration" {
  count = var.api_server_subnet_id != null ? 1 : 0

  triggers = {
    vnet_integration_id = null_resource.enable_vnet_integration[0].id
  }

  provisioner "local-exec" {
    interpreter = local.local_exec_interpreter
    command     = <<-EOT
      ${local.az_federated_login}

        Write-Host "Stopping AKS cluster (~5-7 min)..."
        az aks stop --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --output none
        # Verify cluster is actually stopped (don't trust exit code)
        $stopped = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "powerState.code" -o tsv
        if ($stopped -ne "Stopped") { throw "Cluster did not reach Stopped state (got: '$stopped')" }

        Write-Host "Starting AKS cluster (~5-7 min)..."
        az aks start --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --output none
        $started = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "powerState.code" -o tsv
        if ($started -ne "Running") { throw "Cluster did not reach Running state (got: '$started')" }
        Write-Host "Cluster restart complete."
      ${local.az_login_cleanup}
    EOT
  }

  depends_on = [
    null_resource.enable_vnet_integration,
  ]
}

resource "null_resource" "enable_kms" {
  count = var.kms_key_id != null && var.api_server_subnet_id != null ? 1 : 0

  triggers = {
    cluster_id   = azurerm_kubernetes_cluster.this.id
    key_id       = var.kms_key_id
    key_vault_id = var.kms_key_vault_id
  }

  provisioner "local-exec" {
    interpreter = local.local_exec_interpreter
    command     = <<-EOT
      ${local.az_federated_login}

        # Idempotency: skip update only when BOTH KMS is enabled AND
        # cluster is in a healthy provisioningState. If Failed (e.g. a
        # previous KMS attempt left partial state due to RBAC issues),
        # re-run the update to recover.
        $currentKms = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "securityProfile.azureKeyVaultKms.enabled" -o tsv 2>$null
        $currentState = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "provisioningState" -o tsv 2>$null
        if ($currentKms -eq "true" -and $currentState -eq "Succeeded") {
          Write-Host "KMS Private already enabled and cluster healthy - skipping az aks update."
        } else {
          Write-Host "Enabling/recovering KMS Private etcd encryption (kms=$currentKms, state=$currentState, ~3-5 min)..."
          az aks update --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --enable-azure-keyvault-kms --azure-keyvault-kms-key-id ${var.kms_key_id} --azure-keyvault-kms-key-vault-network-access Private --azure-keyvault-kms-key-vault-resource-id ${var.kms_key_vault_id} --yes --output none
        }

        # Verify both KMS enabled AND cluster healthy.
        $verified = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "securityProfile.azureKeyVaultKms.enabled" -o tsv
        if ($verified -ne "true") { throw "KMS Private state verification failed (got: '$verified')" }
        $provState = az aks show --name ${azurerm_kubernetes_cluster.this.name} --resource-group ${azurerm_kubernetes_cluster.this.resource_group_name} --subscription ${data.azurerm_client_config.current.subscription_id} --query "provisioningState" -o tsv
        if ($provState -eq "Failed") { throw "Cluster is in provisioningState=Failed after KMS update - likely a missing RBAC. Check Azure activity log." }
        Write-Host "KMS Private etcd encryption confirmed enabled (provisioningState: $provState)."
      ${local.az_login_cleanup}
    EOT
  }

  depends_on = [
    null_resource.restart_after_vnet_integration,
  ]
}
