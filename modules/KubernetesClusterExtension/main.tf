###############################################################
# MODULE: KubernetesClusterExtension - Main
#
# One ARM-managed extension on the target AKS cluster.
# Prerequisite resource providers (the caller must register if
# not already done at sub level):
#   - Microsoft.KubernetesConfiguration
#   - Microsoft.Kubernetes
#   - Microsoft.ContainerService
###############################################################

resource "azurerm_kubernetes_cluster_extension" "this" {
  name           = var.name
  cluster_id     = var.cluster_id
  extension_type = var.extension_type

  release_namespace = var.release_namespace
  target_namespace  = var.target_namespace

  release_train = var.release_train
  version       = var.extension_version

  configuration_settings           = var.configuration_settings
  configuration_protected_settings = var.configuration_protected_settings

  dynamic "plan" {
    for_each = var.plan != null ? [var.plan] : []
    content {
      name           = plan.value.name
      product        = plan.value.product
      publisher      = plan.value.publisher
      promotion_code = plan.value.promotion_code
      version        = plan.value.version
    }
  }
}

###############################################################
# RESOURCE: Management Lock (optional) — F-7
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_kubernetes_cluster_extension.this.id
      lock_level = var.lock.kind
      name       = try(var.lock.name, null)
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment — F-3
#
# scope defaults to the extension resource itself. Set each.value.scope
# to an external resource ID (ACR, KV, Storage) to grant the extension's
# MSI access to that resource — use module.kce.aks_assigned_identity[0].principal_id
# as the principal_id in that case.
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = each.value.scope != null ? each.value.scope : azurerm_kubernetes_cluster_extension.this.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}
