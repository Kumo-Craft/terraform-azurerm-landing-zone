###############################################################
# MODULE: NatGateway - Main
# Description: Azure NAT Gateway StandardV2 (zone-redundant)
#              with associated Public IP via azapi provider
#              (azurerm does not yet support StandardV2 SKU)
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# Convention: ng-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    ng-con-prod-gwc-untrust
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
  name = var.name != null ? var.name : module.naming["this"].result.nat_gateway.name

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Public IP — base (zone-redundant, StandardV2 SKU)
###############################################################
resource "azapi_resource" "public_ip" {
  type      = "Microsoft.Network/publicIPAddresses@2025-03-01"
  name      = "pip-${local.name}"
  location  = var.location
  parent_id = var.resource_group_id
  tags      = local.common_tags

  body = {
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
    sku = {
      name = "StandardV2"
      tier = "Regional"
    }
    zones = var.zones
  }

  response_export_values = ["properties.ipAddress"]
}

###############################################################
# RESOURCE: Public IP — additional (optional, multi-PIP support)
###############################################################
resource "azapi_resource" "additional_public_ip" {
  for_each = var.additional_public_ips

  type      = "Microsoft.Network/publicIPAddresses@2025-03-01"
  name      = "pip-${local.name}-${each.key}"
  location  = var.location
  parent_id = var.resource_group_id
  tags      = local.common_tags

  body = {
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
    sku = {
      name = "StandardV2"
      tier = "Regional"
    }
    zones = each.value.zones != null ? each.value.zones : var.zones
  }

  response_export_values = ["properties.ipAddress"]
}

###############################################################
# RESOURCE: NAT Gateway (StandardV2, zone-redundant)
###############################################################
resource "azapi_resource" "nat_gateway" {
  type      = "Microsoft.Network/natGateways@2025-03-01"
  name      = local.name
  location  = var.location
  parent_id = var.resource_group_id
  tags      = local.common_tags

  body = {
    properties = {
      idleTimeoutInMinutes = var.idle_timeout_in_minutes
      publicIpAddresses = concat(
        [{ id = azapi_resource.public_ip.id }],
        [for pip in azapi_resource.additional_public_ip : { id = pip.id }],
      )
      publicIpPrefixes = [for id in values(var.public_ip_prefix_ids) : { id = id }]
    }
    sku = {
      name = "StandardV2"
    }
    zones = var.zones
  }
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azapi_resource.nat_gateway.id
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

  scope                            = azapi_resource.nat_gateway.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
