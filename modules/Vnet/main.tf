###############################################################
# MODULE: Vnet - Main
# Description: Azure Virtual Network with optional inline subnets
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# Convention: vnet-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    vnet-con-prod-gwc-hub
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
  name = var.name != null ? var.name : module.naming["this"].result.virtual_network.name
}

###############################################################
# RESOURCE: Virtual Network
###############################################################
resource "azurerm_virtual_network" "this" {
  name                = local.name
  address_space       = var.address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_servers         = var.dns_servers

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection && var.ddos_protection_plan_id != null ? [var.ddos_protection_plan_id] : []
    content {
      enable = var.enable_ddos_protection
      id     = ddos_protection_plan.value
    }
  }

  dynamic "ip_address_pool" {
    for_each = var.ip_address_pool != null ? [var.ip_address_pool] : []
    content {
      id                     = ip_address_pool.value.id
      number_of_ip_addresses = tostring(ip_address_pool.value.number_of_ip_addresses)
    }
  }

  dynamic "encryption" {
    for_each = var.encryption_enforcement != null ? [var.encryption_enforcement] : []
    content {
      enforcement = encryption.value
    }
  }

  flow_timeout_in_minutes = var.flow_timeout_in_minutes

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_virtual_network.this.id
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

  scope                            = azurerm_virtual_network.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

###############################################################
# RESOURCE: Inline Subnets (optional)
#
# Uses azapi_resource so the subnet is created WITH NSG / RT / NAT GW
# / delegations / service endpoints in a single API call. The classic
# 2-step pattern (azurerm_subnet THEN azurerm_subnet_*_association) is
# blocked by the Azure Policy "Subnets must have a Network Security
# Group" (Deny effect) — between the create and the NSG association
# the subnet exists without NSG, which the policy rejects.
###############################################################
resource "azapi_resource" "subnet" {
  for_each = { for s in var.subnets : s.name => s }

  type      = "Microsoft.Network/virtualNetworks/subnets@2025-03-01"
  name      = each.value.name
  parent_id = azurerm_virtual_network.this.id

  body = {
    properties = {
      addressPrefixes = each.value.address_prefixes
      networkSecurityGroup = each.value.nsg_id != null ? {
        id = each.value.nsg_id
      } : null
      routeTable = each.value.route_table_id != null ? {
        id = each.value.route_table_id
      } : null
      natGateway = each.value.nat_gateway_id != null ? {
        id = each.value.nat_gateway_id
      } : null
      serviceEndpoints = each.value.service_endpoints != null ? [
        for svc in each.value.service_endpoints : { service = svc }
      ] : []
      privateEndpointNetworkPolicies = each.value.private_endpoint_network_policies
      defaultOutboundAccess          = each.value.default_outbound_access_enabled
      ipamPoolPrefixAllocations = each.value.ip_address_pool != null ? [
        {
          pool                = { id = each.value.ip_address_pool.id }
          numberOfIpAddresses = tostring(each.value.ip_address_pool.number_of_ip_addresses)
        }
      ] : []
      # Azure auto-populates `actions` from serviceName; only serviceName is needed.
      delegations = [
        for d in each.value.delegations : {
          name = d.name
          properties = {
            serviceName = d.service_name
          }
        }
      ]
    }
  }
}
