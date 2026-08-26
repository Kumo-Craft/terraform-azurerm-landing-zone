###############################################################
# MODULE: PrivateEndpoint - Main
# Description: Creates Azure Private Endpoints for PaaS services
###############################################################

resource "time_static" "time" {}

###############################################################
# RESOURCE: Private Endpoints
###############################################################
resource "azurerm_private_endpoint" "this" {
  for_each = var.private_endpoints

  name                          = each.value.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.subnet_id
  custom_network_interface_name = each.value.custom_network_interface_name

  private_service_connection {
    name                              = "psc-${each.value.name}"
    private_connection_resource_id    = each.value.resource_id
    private_connection_resource_alias = each.value.resource_alias
    subresource_names                 = each.value.subresource_names
    is_manual_connection              = each.value.is_manual_connection
    request_message                   = each.value.request_message
  }

  dynamic "ip_configuration" {
    for_each = each.value.private_ip_address != null ? [1] : []
    content {
      name               = "ipc-${each.value.name}"
      private_ip_address = each.value.private_ip_address
      # subresource_name only applies to resource_id-based PEs (the
      # provider rejects it for alias-based PSC connections, where the
      # PLS owner has already defined the subresource topology).
      subresource_name = length(each.value.subresource_names) > 0 ? each.value.subresource_names[0] : null
      member_name      = each.value.member_name
    }
  }

  dynamic "private_dns_zone_group" {
    for_each = each.value.private_dns_zone_group != null ? [each.value.private_dns_zone_group] : []
    content {
      name                 = private_dns_zone_group.value.name
      private_dns_zone_ids = private_dns_zone_group.value.private_dns_zone_ids
    }
  }

  # Ignore private_dns_zone_group managed by ALZ DINE Policy
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }

  tags = merge(
    var.tags,
    each.value.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
      # TargetResource: the resource_id when set, otherwise the alias
      # (so callers always see something useful in the Azure portal).
      TargetResource = coalesce(each.value.resource_id, each.value.resource_alias)
      # SubresourceType: empty string for alias-based PEs (no subresource list).
      SubresourceType = join(",", each.value.subresource_names)
    }
  )
}

