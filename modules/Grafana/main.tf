###############################################################
# MODULE: Grafana - Main
# Description: Azure Managed Grafana with identity, RBAC,
#              and Azure Monitor Workspace integration
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — via ../Naming submodule (dashboard_grafana type).
# Convention: amg-{sub}-{env}-{region}-{workload}
# The for_each guard ensures the Naming module is only instantiated
# when var.name is null — avoids "Invalid index" in plan-time tests.
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
  name = var.name != null ? var.name : module.naming["this"].result.dashboard_grafana.name

  # PE name: pep-{sub}-{env}-{region}-grafana (fall back to var.name prefix when override used)
  pe_name = var.name != null ? "pep-${var.name}" : "pep-${join("-", slice(module.naming["this"].suffix, 0, 3))}-grafana"

  # Zone redundancy: explicit override wins; otherwise env-driven (true for prod).
  # NOTE: zone_redundancy_enabled is Azure-immutable after create — cannot change without recreate.
  zone_redundancy_enabled = var.zone_redundancy_enabled != null ? var.zone_redundancy_enabled : var.environment == "prod"

  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Identity Role Assignments — delegated to ../RoleAssignment
###############################################################
module "identity_role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.identity_role_assignments

  scope                                  = each.value.scope
  principal_id                           = var.user_assigned_identity_principal_id
  principal_type                         = "ServicePrincipal"
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}

###############################################################
# RESOURCE: Azure Managed Grafana
###############################################################
resource "azurerm_dashboard_grafana" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  grafana_major_version             = var.grafana_major_version
  sku                               = var.grafana_sku
  zone_redundancy_enabled           = local.zone_redundancy_enabled
  api_key_enabled                   = var.api_key_enabled
  deterministic_outbound_ip_enabled = var.deterministic_outbound_ip_enabled
  public_network_access_enabled     = var.public_network_access_enabled

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  dynamic "azure_monitor_workspace_integrations" {
    for_each = var.azure_monitor_workspace_ids
    iterator = amw_id
    content {
      resource_id = amw_id.value
    }
  }

  tags = local.common_tags

  # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.82 systemic sweep).
  # Grafana destruction loses all dashboards + data source bindings + user-stored
  # state. AAD-managed but RBAC + folder layout are operator-time-consuming to
  # reconstruct. Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Grafana RBAC — delegated to ../RoleAssignment
###############################################################
module "grafana_admin" {
  source   = "../RoleAssignment"
  for_each = toset(var.grafana_admin_group_object_ids)

  scope                = azurerm_dashboard_grafana.this.id
  principal_id         = each.value
  principal_type       = "Group"
  role_definition_name = "Grafana Admin"
}

module "grafana_editor" {
  source   = "../RoleAssignment"
  for_each = toset(var.grafana_editor_group_object_ids)

  scope                = azurerm_dashboard_grafana.this.id
  principal_id         = each.value
  principal_type       = "Group"
  role_definition_name = "Grafana Editor"
}

module "grafana_viewer" {
  source   = "../RoleAssignment"
  for_each = toset(var.grafana_viewer_group_object_ids)

  scope                = azurerm_dashboard_grafana.this.id
  principal_id         = each.value
  principal_type       = "Group"
  role_definition_name = "Grafana Viewer"
}

###############################################################
# RESOURCE: Private Endpoint
###############################################################
resource "azurerm_private_endpoint" "this" {
  count = var.private_endpoint != null ? 1 : 0

  name                          = local.pe_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint.subnet_id
  custom_network_interface_name = var.private_endpoint.custom_network_interface_name

  private_service_connection {
    name                           = "psc-${local.pe_name}"
    private_connection_resource_id = azurerm_dashboard_grafana.this.id
    subresource_names              = ["grafana"]
    is_manual_connection           = false
  }

  dynamic "ip_configuration" {
    for_each = var.private_endpoint.private_ip_address != null ? [1] : []
    content {
      name               = "ipc-${local.pe_name}"
      private_ip_address = var.private_endpoint.private_ip_address
      subresource_name   = "grafana"
      member_name        = "default"
    }
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_endpoint.private_dns_zone_ids != null ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = var.private_endpoint.private_dns_zone_ids
    }
  }

  # Ignore private_dns_zone_group managed by ALZ DINE Policy + the
  # CreatedOn tag that's re-evaluated every plan via formatdate().
  lifecycle {
    ignore_changes = [private_dns_zone_group, tags["CreatedOn"]]
  }

  tags = merge(
    local.common_tags,
    {
      TargetResource  = azurerm_dashboard_grafana.this.id
      SubresourceType = "grafana"
    }
  )
}

###############################################################
# RESOURCE: Managed Private Endpoints (Grafana egress → e.g. AMPLS)
# Required when target data sources (LAW, AMW) are reachable only
# via Private Link / NSP — Grafana SaaS egress IPs cannot otherwise
# reach them. Azure auto-enables the managed VNet on first MPE.
###############################################################
resource "azurerm_dashboard_grafana_managed_private_endpoint" "this" {
  for_each = var.managed_private_endpoints

  grafana_id = azurerm_dashboard_grafana.this.id
  name       = "mpe-${each.key}"
  location   = var.location

  lifecycle {
    precondition {
      condition     = length("mpe-${each.key}") <= 20 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", "mpe-${each.key}"))
      error_message = "MPE name 'mpe-${each.key}' must be 2-20 chars, start with a letter, end with letter/digit, alphanumerics + dashes only. Shorten the map key (max 16 chars)."
    }
  }
  private_link_resource_id     = each.value.private_link_resource_id
  group_ids                    = each.value.group_ids
  private_link_resource_region = each.value.private_link_resource_region
  private_link_service_url     = each.value.private_link_service_url
  request_message              = each.value.request_message

  tags = local.common_tags
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_dashboard_grafana.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
