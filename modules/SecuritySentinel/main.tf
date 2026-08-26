###############################################################
# SecuritySentinel - dedicated SOC workspace
###############################################################
# Creates: Log Analytics Workspace (private) + Microsoft Sentinel
#          onboarding + optional data connectors.
# NO daily cap by default (a cap on a Sentinel workspace blinds
# the SOC during a spike — Microsoft guidance).
###############################################################

locals {
  # House `law-` prefix (NOT the upstream Naming `log-` slug) — passed to the
  # composed module as a name override so the workspace name is preserved
  # byte-for-byte. Same pattern as NetworkStack's rt-/nw- overrides.
  law_name = "law-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"
}

# ── Log Analytics Workspace (Sentinel backend) ───────────────
# Composed from the canonical ../LogAnalyticsWorkspace leaf. The leaf owns
# the resource + its secure defaults; this module keeps the Sentinel-specific
# posture (no daily cap, 90-day retention) via its own variables.
# State-safe via the `moved` block below.
module "law" {
  source = "../LogAnalyticsWorkspace"

  name                = local.law_name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days
  daily_quota_gb    = var.daily_quota_gb

  internet_ingestion_enabled = var.law_internet_ingestion_enabled
  internet_query_enabled     = var.law_internet_query_enabled
  # The caller-facing variable keeps the "disabled" semantics; the leaf takes
  # the positive form (local_authentication_disabled is removed in azurerm v5).
  local_authentication_enabled    = !var.law_local_authentication_disabled
  allow_resource_only_permissions = true

  tags = var.tags
}

moved {
  from = azurerm_log_analytics_workspace.sentinel
  to   = module.law.azurerm_log_analytics_workspace.this
}

# ── Microsoft Sentinel onboarding ────────────────────────────
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id                 = module.law.id
  customer_managed_key_enabled = var.enable_cmk
}

# ── Data connectors (opt-in) ─────────────────────────────────
resource "azurerm_sentinel_data_connector_azure_active_directory" "entra" {
  count                      = var.connectors.entra_id ? 1 : 0
  name                       = "entra-id"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  tenant_id                  = var.connector_tenant_id
}

resource "azurerm_sentinel_data_connector_azure_security_center" "defender" {
  count                      = var.connectors.defender_for_cloud ? 1 : 0
  name                       = "defender-for-cloud"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  subscription_id            = var.connector_subscription_id
}