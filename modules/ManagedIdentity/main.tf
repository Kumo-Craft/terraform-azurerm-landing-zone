###############################################################
# MODULE: ManagedIdentity - Main
# Description: User Assigned Managed Identity Azure
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output with the house literal prefix `id-` (Azure/naming
# uses `uai-` — divergent, so we keep the literal to avoid state churn).
# Convention: id-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    id-api-prod-gwc-aks
#
# Naming divergence: we use literal "id-" prefix + module.naming["this"].suffix list
# instead of module.naming["this"].result.user_assigned_identity.name (which yields "uai-").
# House convention is "id-" not the upstream Azure/naming/azurerm "uai-". Changing this
# would cause state churn for existing UAMIs.
# NF/F-10 (v0.2.38 review): future versions could add a custom_names override in
# ../Naming to route this through the validated upstream output instead of suffix
# concat. Not pursued now (additive deferral).
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
  name = var.name != null ? var.name : "id-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: User Assigned Managed Identity
###############################################################
resource "azurerm_user_assigned_identity" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_user_assigned_identity.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Federated Identity Credentials (Workload Identity)
###############################################################
resource "azurerm_federated_identity_credential" "this" {
  for_each = var.federated_identity_credentials

  name                      = each.value.name
  user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  audience                  = each.value.audience
  issuer                    = each.value.issuer
  subject                   = each.value.subject
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  principal_id                           = azurerm_user_assigned_identity.this.principal_id
  principal_type                         = "ServicePrincipal"
  scope                                  = each.value.scope
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

moved {
  from = azurerm_role_assignment.this
  to   = module.role_assignments.azurerm_role_assignment.this
}
