###############################################################
# MODULE: ContainerRegistry - Main
# Description: Azure Container Registry (ACR) with lock and RBAC
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output (centralized input validation) with the house
# literal prefix `cr` (Azure/naming uses `acr` — divergent, so we
# keep the literal to avoid state churn).
#
# Convention (unchanged from previous implementation):
#   cr{subscription_acronym}{environment}{region_code}{workload}
# Note: ACR name must be alphanumeric only, no hyphens!
# Example:
#   crapiprodgwc001
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
  # F-1 plan-time bug fix: guard module.naming["this"] reference with ternary.
  # When var.name != null, module.naming has for_each = toset([]) so
  # module.naming["this"] doesn't exist — unguarded reference would cause
  # "Invalid index" plan error. Same fix as DdosProtection v0.2.79 F-1
  # (cross-module systemic sweep — Truth #11 methodology).
  computed_name                      = var.name != null ? "" : "cr${join("", module.naming["this"].suffix)}"
  name                               = var.name != null ? var.name : local.computed_name
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

###############################################################
# RESOURCE: Container Registry
###############################################################
resource "azurerm_container_registry" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku

  admin_enabled                 = var.admin_enabled
  public_network_access_enabled = var.public_network_access_enabled

  # CKV_AZURE_233 (ACR zone redundancy): satisfied by default —
  # var.zone_redundancy_enabled defaults to true and each georeplication
  # defaults zone_redundancy_enabled = true, so the registry is zone-redundant
  # out of the box. The value is intentionally wrapped in a Premium-only SKU
  # guard (Azure rejects the property on Basic/Standard) which Checkov's static
  # analyzer cannot resolve; on non-Premium SKUs the control is not applicable.
  # checkov:skip=CKV_AZURE_233: zone_redundancy_enabled defaults to true (zone-redundant by default); SKU-guarded to Premium because Azure rejects the property on Basic/Standard, and Checkov cannot evaluate the conditional. N/A on non-Premium.
  zone_redundancy_enabled = var.sku == "Premium" ? var.zone_redundancy_enabled : null
  data_endpoint_enabled   = var.sku == "Premium" ? var.data_endpoint_enabled : null

  # Premium-only security/lifecycle toggles. Azure rejects them on
  # Basic/Standard, so we set null when the SKU isn't Premium.
  retention_policy_in_days = var.sku == "Premium" ? var.retention_policy_in_days : null

  # CKV_AZURE_164 (ACR signed/trusted images): NOT remediated by enabling
  # trust_policy — Docker Content Trust (DCT) is deprecated by Azure. Per MS
  # Learn (container-registry-content-trust-deprecation): DCT cannot be enabled
  # on new / never-enabled registries after 2026-05-31 and is fully retired on
  # 2028-03-31. Forcing trust_policy_enabled = true would make every new registry
  # creation fail at the Azure API. Image signing is instead delegated to the
  # Notary Project (notation) — an out-of-band control not modeled by azurerm.
  # Kept configurable (default false) only for pre-existing registries.
  # checkov:skip=CKV_AZURE_164: Docker Content Trust is deprecated; per MS Learn it cannot be enabled on new registries after 2026-05-31 and is retired 2028-03-31 — enabling it would fail registry creation. Signing is delegated to Notary Project (notation), out-of-band and not modeled by azurerm.
  trust_policy_enabled = var.sku == "Premium" ? var.trust_policy_enabled : null

  # CKV_AZURE_166 (image quarantine): NOT defaulted on. Quarantine is an ACR
  # PREVIEW feature; once enabled, every pushed image is quarantined and ALL
  # pulls fail until an external scan + AcrQuarantineWriter orchestrator marks
  # each image "verified" (infra this module cannot provision — see MS Learn
  # container-registry-check-health / FAQ). Defaulting it on would render every
  # registry unusable out of the box. Left configurable (default false) for
  # callers that operate a verify pipeline.
  # checkov:skip=CKV_AZURE_166: quarantine_policy is an ACR preview feature; enabling it blocks ALL image pulls until an external scan + AcrQuarantineWriter orchestrator (not provisionable by this module) marks images verified. Defaulting it on would brick every registry. Opt-in via var.quarantine_policy_enabled.
  quarantine_policy_enabled = var.sku == "Premium" ? var.quarantine_policy_enabled : null
  anonymous_pull_enabled    = var.anonymous_pull_enabled
  export_policy_enabled     = var.sku == "Premium" ? var.export_policy_enabled : null

  network_rule_bypass_option = var.network_rule_bypass_option

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = var.identity_ids
    }
  }

  dynamic "encryption" {
    for_each = var.customer_managed_key != null ? [var.customer_managed_key] : []
    content {
      key_vault_key_id   = encryption.value.key_vault_key_id
      identity_client_id = encryption.value.identity_client_id
    }
  }

  dynamic "georeplications" {
    for_each = var.georeplications
    content {
      location                  = georeplications.value.location
      zone_redundancy_enabled   = georeplications.value.zone_redundancy_enabled
      regional_endpoint_enabled = georeplications.value.regional_endpoint_enabled
      tags                      = georeplications.value.tags
    }
  }

  dynamic "network_rule_set" {
    for_each = var.network_rule_set != null ? [var.network_rule_set] : []
    content {
      default_action = network_rule_set.value.default_action

      dynamic "ip_rule" {
        for_each = network_rule_set.value.ip_rule
        content {
          action   = ip_rule.value.action
          ip_range = ip_rule.value.ip_range
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    prevent_destroy = true

    # Premium-only feature usage check at plan time. Caller can still
    # downgrade to Basic/Standard, but only when no Premium-only feature
    # is actively enabled.
    precondition {
      condition = var.sku == "Premium" || (
        var.customer_managed_key == null &&
        var.retention_policy_in_days == null &&
        var.trust_policy_enabled == false &&
        length(var.georeplications) == 0 &&
        var.network_rule_set == null
      )
      error_message = "customer_managed_key, retention_policy_in_days, trust_policy_enabled, georeplications and network_rule_set all require sku = \"Premium\". Set sku to Premium or unset these inputs."
    }

    # CMK requires at least one UAMI to read from Key Vault.
    precondition {
      condition     = var.customer_managed_key == null || length(var.identity_ids) > 0
      error_message = "customer_managed_key requires at least one entry in identity_ids (the User-Assigned MI granted Key Vault Crypto User on the KV)."
    }

    # Export policy / public network coupling (MS Learn: data-loss-prevention).
    # Azure requires public_network_access_enabled = false in order to set
    # export_policy_enabled = false. On Premium, a caller who sets public=true
    # while leaving export=false (the new secure default) would get an Azure API
    # error — catch it at plan time. Scoped to Premium: export_policy_enabled is
    # null-guarded to Premium (see resource above), so on Basic/Standard the
    # value never reaches Azure and public=true is a valid combination.
    precondition {
      condition     = var.sku != "Premium" || var.export_policy_enabled == true || var.public_network_access_enabled == false
      error_message = "export_policy_enabled = false requires public_network_access_enabled = false (Azure constraint: to disable artifact export, public network access must also be disabled — see https://aka.ms/acr/export-policy)."
    }

    # anonymous_pull_enabled is only supported on Standard and Premium SKUs.
    # Default is false so Basic callers pass without any action required.
    precondition {
      condition     = var.anonymous_pull_enabled == false || contains(["Standard", "Premium"], var.sku)
      error_message = "anonymous_pull_enabled = true requires sku = \"Standard\" or \"Premium\" (Basic SKU does not support anonymous pull)."
    }

    # Private Link for ACR is a Premium-only feature (MS Learn:
    # container-registry-private-endpoints). Guard at plan time.
    precondition {
      condition     = length(var.private_endpoints) == 0 || var.sku == "Premium"
      error_message = "private_endpoints require sku = \"Premium\" (ACR Private Link is a Premium-only feature)."
    }
  }
}

###############################################################
# RESOURCE: Diagnostic Setting (optional, single LAW destination)
###############################################################
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostic_setting != null ? 1 : 0

  name                       = var.diagnostic_setting.name
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.diagnostic_setting.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = var.diagnostic_setting.categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = var.diagnostic_setting.metrics_enabled ? ["AllMetrics"] : []
    content {
      category = enabled_metric.value
    }
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_container_registry.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = azurerm_container_registry.this.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}

###############################################################
# RESOURCE: Private Endpoints — delegated to ../PrivateEndpoint
# Target sub-resource "registry"; DNS zone privatelink.azurecr.io.
# One PrivateEndpoint module instance per entry (each may use its
# own subnet). ACR Private Link requires the Premium SKU.
###############################################################
module "private_endpoint" {
  source   = "../PrivateEndpoint"
  for_each = var.private_endpoints

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value.subnet_id
  tags                = var.tags

  private_endpoints = {
    (each.key) = {
      name                          = coalesce(each.value.name, "pe-${local.name}-${each.key}")
      resource_id                   = azurerm_container_registry.this.id
      subresource_names             = ["registry"]
      member_name                   = each.value.member_name
      private_ip_address            = each.value.private_ip_address
      custom_network_interface_name = each.value.custom_network_interface_name
      private_dns_zone_group = each.value.private_dns_zone_ids != null ? {
        name                 = "default"
        private_dns_zone_ids = each.value.private_dns_zone_ids
      } : null
      tags = each.value.tags
    }
  }
}

# v0.2.83: moved block REMOVED per Truth #3 (for_each modules with dynamic
# keys cannot have static moved blocks — Terraform cannot enumerate the keys
# at moved-block parse time). Same fix as AksStack v0.2.66 F-11 +
# PaloCluster v0.2.73 F-1+F-3 + ResourceGroup v0.2.76 F-1.
#
# Callers with pre-v0.2.83 state at `azurerm_role_assignment.this["<key>"]`
# must manually migrate per principal:
#
#   terraform state mv \
#     'module.<caller>.azurerm_role_assignment.this["<principal_oid>"]' \
#     'module.<caller>.module.role_assignments["<principal_oid>"].azurerm_role_assignment.this'
#
# Skip this step if the module was first deployed at v0.2.X+ (where X = the
# version that introduced the ../RoleAssignment composition).
