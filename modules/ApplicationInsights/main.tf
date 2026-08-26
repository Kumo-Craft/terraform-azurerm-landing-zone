###############################################################
# MODULE: ApplicationInsights - Main
# Description: Workspace-based Azure Application Insights
#              (classic mode is retired). Backed by a caller-
#              provided Log Analytics workspace.
###############################################################

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output with the house literal prefix `appi-` (Azure/naming
# v0.4.3 has no `application_insights` output type, so we build manually).
# Convention: appi-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    appi-mgm-prod-frc-sre-01
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
  # Single guarded local — module.naming["this"] only exists when var.name == null.
  # When var.name is supplied (escape hatch), the for_each is empty and referencing
  # module.naming["this"] directly would cause an "Invalid index" plan error.
  name = var.name != null ? var.name : "appi-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: Application Insights (workspace-based)
###############################################################
resource "azurerm_application_insights" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Workspace-based: telemetry is stored in this Log Analytics workspace.
  workspace_id     = var.workspace_id
  application_type = var.application_type

  retention_in_days   = var.retention_in_days
  sampling_percentage = var.sampling_percentage

  # The provider deprecated `local_authentication_disabled` in favour of
  # `local_authentication_enabled`. We keep the disable-oriented module var but
  # wire it to the non-deprecated attribute via negation. Null keeps the
  # provider default (local auth enabled). Set the var true to enforce Entra-only.
  local_authentication_enabled = var.local_authentication_disabled == null ? null : !var.local_authentication_disabled

  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  tags = var.tags
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_application_insights.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_application_insights.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
