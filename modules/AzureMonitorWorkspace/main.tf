###############################################################
# MODULE: AzureMonitorWorkspace - Main
# Description: Azure Monitor Workspace (Managed Prometheus)
#              with optional Private Endpoint
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output with the house literal prefix `amw-` (Azure/naming
# v0.4.3 has no `monitor_workspace` output type, so we build manually).
# Convention: amw-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    amw-mgm-prod-gwc-01
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
  name = var.name != null ? var.name : "amw-${join("-", module.naming["this"].suffix)}"

  # PE name prefix: pep-{acr}-{env}-{region}-amw-{workload}.
  # Guard mirrors local.name: only reference module.naming["this"] when it exists.
  pe_prefix = var.name != null ? var.name : join("-", slice(module.naming["this"].suffix, 0, 3))
}

###############################################################
# RESOURCE: Azure Monitor Workspace
###############################################################
resource "azurerm_monitor_workspace" "this" {
  name                          = local.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  public_network_access_enabled = var.public_network_access_enabled

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # AMW destruction loses all Prometheus metrics + Grafana data source +
  # ContainerInsights collection. Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Private Endpoint (prometheusMetrics)
###############################################################
resource "azurerm_private_endpoint" "this" {
  count = var.subnet_id != null ? 1 : 0

  name                = "pep-${local.pe_prefix}-amw-${var.workload}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-pep-${local.pe_prefix}-amw-${var.workload}"
    private_connection_resource_id = azurerm_monitor_workspace.this.id
    subresource_names              = ["prometheusMetrics"]
    is_manual_connection           = false
  }

  # Optional explicit DNS zone group. Managed Prometheus uses a REGIONAL zone
  # (privatelink.<region>.prometheus.monitor.azure.com) which the ALZ DINE
  # initiative Deploy-Private-DNS-Zones does NOT currently cover — so on subs
  # where that zone is not auto-linked, the PE's zone group stays empty and
  # private resolution fails (no such host). Passing private_dns_zone_ids
  # manages the zone group in TF. Empty (default) = left to the DINE policy.
  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Kept for DINE back-compat: PEs that rely on the ALZ policy to post the zone
  # group must not see TF try to remove it. NOTE the trade-off: on an ALREADY
  # EXISTING PE, newly setting var.private_dns_zone_ids will NOT take effect on
  # a plain apply (the update diff on private_dns_zone_group is ignored) — it
  # requires `terraform apply -replace=module.<x>.azurerm_private_endpoint.this[0]`
  # to recreate the PE (non-destructive for the AMW, which has prevent_destroy).
  # On a NEW AMW the zone group is posted at creation time.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_workspace.this.id
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

  scope                            = azurerm_monitor_workspace.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
