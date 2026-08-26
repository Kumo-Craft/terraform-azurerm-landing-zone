###############################################################
# MODULE: SubnetWithNsg - Main
# Description: Creates subnets with NSG in a single Azure API call
#
# Uses azapi_resource instead of azurerm_subnet because Azure
# Policy "Subnets must have a Network Security Group" (Deny)
# blocks the standard two-step approach (create subnet, then
# associate NSG).
###############################################################

locals {
  # Merge legacy single `delegation` (deprecated) with new `delegations` list.
  # Each subnet ends up with a single concatenated, deduped delegation list.
  effective_subnets = {
    for s in var.subnets : s.name => merge(s, {
      effective_delegations = concat(
        s.delegation != null ? [s.delegation] : [],
        s.delegations,
      )
    })
  }

  # Flatten per-subnet role_assignments into a single map keyed by
  # "<subnet_name>.<assignment_key>" for use with module.rbac for_each.
  flat_role_assignments = merge([
    for sk, sv in local.effective_subnets : {
      for rk, rv in sv.role_assignments :
      "${sk}.${rk}" => merge(rv, { subnet_key = sk })
    }
  ]...)
}

resource "azapi_resource" "subnet" {
  for_each = local.effective_subnets

  type      = "Microsoft.Network/virtualNetworks/subnets@2025-03-01"
  name      = each.value.name
  parent_id = var.virtual_network_id

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
      serviceEndpoints = [
        for svc in each.value.service_endpoints : { service = svc }
      ]
      privateEndpointNetworkPolicies = each.value.private_endpoint_network_policies
      defaultOutboundAccess          = each.value.default_outbound_access_enabled
      ipamPoolPrefixAllocations = each.value.ip_address_pool != null ? [
        {
          pool                = { id = each.value.ip_address_pool.id }
          numberOfIpAddresses = tostring(each.value.ip_address_pool.number_of_ip_addresses)
        }
      ] : []
      delegations = [
        for d in each.value.effective_delegations : {
          name = d.name
          properties = {
            serviceName = d.service_name
          }
        }
      ]
    }
  }
}

###############################################################
# RESOURCE: Management Locks — per-subnet, delegated to ../ResourceLock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = {
    for k, v in local.effective_subnets :
    k => {
      scope      = azapi_resource.subnet[k].id
      lock_level = v.lock.kind
      name       = v.lock.name
    }
    if v.lock != null
  }
}

###############################################################
# RESOURCE: Role Assignments — per-subnet, delegated to ../RoleAssignment
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = local.flat_role_assignments

  scope                            = azapi_resource.subnet[each.value.subnet_key].id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
