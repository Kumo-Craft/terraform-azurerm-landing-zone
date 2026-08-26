###############################################################
# Module AlzManagement - Log Analytics + Automation + Sentinel
###############################################################
# Wraps Azure/avm-ptn-alz-management/azurerm
# Creates: LAW, Automation Account (inerte, imposée par l'AVM), DCRs (AMA),
#          Solutions, Sentinel, User Assigned Identity (ama)
###############################################################

resource "time_static" "time" {}

###############################################################
# Optional: Inline Resource Group Creation
###############################################################
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = "rg-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.resource_group_workload}"
  location = var.location
  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.77). When count=1
  # this module creates the ALZ Management RG hosting subscription-level resources
  # (LAW + AMW + Defender configs). Destruction cascades to every resource inside.
  # When count=0 the resource doesn't exist — prevent_destroy is moot.
  # Same systemic protection as ResourceGroup v0.2.76 (which closed this gap for
  # the BASE RG module). Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

# Data source: caller-provided RG (used when create_resource_group = false, e.g. for lock scope)
data "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

###############################################################
# Naming — delegated to the in-repo Naming submodule (wrapper
# around Azure/naming/azurerm). Upstream slugs:
#   log_analytics_workspace → log | automation_account → aa
#   user_assigned_identity  → uai | monitor_data_collection_rule → dcr
###############################################################
module "naming" {
  source               = "../Naming"
  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

# Component-qualified names: identities + DCRs carry a trailing
# component segment (law/ama, changetracking/vminsights/defendersql)
# via extra_suffix → {slug}-{acr}-{env}-{region}-{workload}-{component}.
module "naming_component" {
  source   = "../Naming"
  for_each = toset(["ama", "changetracking", "vminsights", "defendersql"])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
  extra_suffix         = [each.value]
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  # Naming — computed via the Naming submodule (see modules above).
  computed_names = {
    law                 = module.naming.result.log_analytics_workspace.name
    aa                  = module.naming.result.automation_account.name
    identity_ama        = module.naming_component["ama"].result.user_assigned_identity.name
    dcr_change_tracking = module.naming_component["changetracking"].result.monitor_data_collection_rule.name
    dcr_vm_insights     = module.naming_component["vminsights"].result.monitor_data_collection_rule.name
    dcr_defender_sql    = module.naming_component["defendersql"].result.monitor_data_collection_rule.name
  }

  # SKU logic: CapacityReservation if > 100GB/day, else PerGB2018
  law_sku = var.log_ingestion_gb_per_day > 100 ? "CapacityReservation" : "PerGB2018"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# AVM ALZ Management Module
###############################################################
module "alz_management" {
  source = "Azure/avm-ptn-alz-management/azurerm"
  # Exact pin (mirror of AlzArchitecture's pinning style). Bump
  # deliberately when the upstream AVM module ships a new minor —
  # ALZ libraries can introduce breaking changes within 0.x.
  version = "0.9.0"

  location                        = var.location
  resource_group_name             = local.resource_group_name
  resource_group_creation_enabled = false

  # ── Log Analytics Workspace ──────────────────────────────────
  log_analytics_workspace_name                               = local.computed_names.law
  log_analytics_workspace_sku                                = local.law_sku
  log_analytics_workspace_reservation_capacity_in_gb_per_day = local.law_sku == "CapacityReservation" ? var.log_ingestion_gb_per_day : null
  log_analytics_workspace_retention_in_days                  = var.log_retention_days
  log_analytics_workspace_daily_quota_gb                     = var.log_daily_quota_gb
  log_analytics_workspace_internet_ingestion_enabled         = var.law_internet_ingestion_enabled
  log_analytics_workspace_internet_query_enabled             = var.law_internet_query_enabled
  log_analytics_workspace_cmk_for_query_forced               = var.enable_cmk
  log_analytics_workspace_local_authentication_enabled       = var.law_local_authentication_enabled
  log_analytics_workspace_allow_resource_only_permissions    = true

  # ── Automation Account ───────────────────────────────────────
  automation_account_name                          = local.computed_names.aa
  automation_account_sku_name                      = "Basic"
  automation_account_local_authentication_enabled  = false
  automation_account_public_network_access_enabled = var.aa_public_network_access_enabled
  # Automation Account RETIRÉE. Dans avm-ptn-alz-management, ce flag gate l'AA
  # elle-même (pas seulement le linked service) → false = AUCUNE Automation Account
  # créée. Raison : Update Management + Change Tracking via Log Analytics retirés
  # (31/08/2024) → Azure Update Manager + CT&I via AMA (DCR change_tracking ci-dessous).
  # Les automation_account_* ci-dessus deviennent inertes ; automation_account_name
  # reste passé car c'est une variable obligatoire de l'AVM.
  linked_automation_account_creation_enabled = false

  # ── Data Collection Rules (Azure Monitor Agent) ──────────────
  data_collection_rules = {
    change_tracking = {
      name     = local.computed_names.dcr_change_tracking
      location = var.location
    }
    vm_insights = {
      name     = local.computed_names.dcr_vm_insights
      location = var.location
    }
    defender_sql = {
      name                                                   = local.computed_names.dcr_defender_sql
      location                                               = var.location
      enable_collection_of_sql_queries_for_security_research = true
    }
  }

  # ── Log Analytics Solutions ──────────────────────────────────
  # ChangeTracking (solution OMSGallery, ère MMA) retirée : la CT&I moderne passe
  # par le DCR AMA (change_tracking) ci-dessus. On garde VMInsights + ContainerInsights.
  log_analytics_solution_plans = [
    { product = "OMSGallery/VMInsights", publisher = "Microsoft" },
    { product = "OMSGallery/ContainerInsights", publisher = "Microsoft" },
  ]

  # ── Microsoft Sentinel ───────────────────────────────────────
  # Sentinel est migré vers une sub Security dédiée (platform/security/Sentinel),
  # alignement CAF. enable_sentinel=false → le LAW management redevient ops-only.
  sentinel_onboarding = var.enable_sentinel ? {
    customer_managed_key_enabled = var.enable_cmk
  } : null

  # ── User Assigned Managed Identities ─────────────────────────
  user_assigned_managed_identities = {
    ama = {
      name     = local.computed_names.identity_ama
      location = var.location
    }
  }

  # ── Tags ─────────────────────────────────────────────────────
  tags = local.common_tags
}

###############################################################
# Resource Locks (LAW + RG)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    law = {
      scope      = module.alz_management.log_analytics_workspace.id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-law" : null
    }
    rg = {
      scope      = var.create_resource_group ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.this[0].id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-rg" : null
    }
  } : {}
}
