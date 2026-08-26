###############################################################
# MODULE: DnsResolver - Main
# Description: Azure DNS Private Resolver with inbound/outbound
#              endpoints and optional forwarding ruleset
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# private_dns_resolver is not a key in Azure/naming/azurerm 0.4.3,
# so we use the inline slug pattern: dnspr-{acr}-{env}-{region}-{workload}
# Example: dnspr-con-prod-gwc-hub
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
  name = var.name != null ? var.name : "dnspr-${join("-", module.naming["this"].suffix)}"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  enable_outbound = var.outbound_subnet_id != null
  enable_ruleset  = local.enable_outbound && length(var.forwarding_rules) > 0
}

###############################################################
# STATE MIGRATION: inline azurerm_resource_group removed in v0.2.55
# The RG is intentionally NOT destroyed — it is now caller-managed.
###############################################################
removed {
  from = azurerm_resource_group.this

  lifecycle {
    destroy = false
  }
}

###############################################################
# RESOURCE: DNS Private Resolver
###############################################################
resource "azurerm_private_dns_resolver" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  virtual_network_id  = var.virtual_network_id
  tags                = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Inbound Endpoint — receives DNS queries from VNets
###############################################################
resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = "in-${local.name}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location

  ip_configurations {
    private_ip_allocation_method = var.inbound_private_ip != null ? "Static" : "Dynamic"
    private_ip_address           = var.inbound_private_ip
    subnet_id                    = var.inbound_subnet_id
  }

  tags = local.common_tags
}

###############################################################
# RESOURCE: Outbound Endpoint — forwards to external DNS
###############################################################
resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  count = local.enable_outbound ? 1 : 0

  name                    = "out-${local.name}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  subnet_id               = var.outbound_subnet_id
  tags                    = local.common_tags
}

###############################################################
# RESOURCE: DNS Forwarding Ruleset
###############################################################
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "this" {
  count = local.enable_ruleset ? 1 : 0

  name                                       = "frs-${local.name}"
  location                                   = var.location
  resource_group_name                        = var.resource_group_name
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.this[0].id]
  tags                                       = local.common_tags
}

###############################################################
# RESOURCE: Forwarding Rules
###############################################################
resource "azurerm_private_dns_resolver_forwarding_rule" "this" {
  for_each = local.enable_ruleset ? var.forwarding_rules : {}

  name                      = each.key
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this[0].id
  domain_name               = each.value.domain_name
  enabled                   = each.value.enabled

  dynamic "target_dns_servers" {
    for_each = each.value.target_dns_servers
    content {
      ip_address = target_dns_servers.value.ip_address
      port       = target_dns_servers.value.port
    }
  }
}

###############################################################
# RESOURCE: VNet Links (links ruleset to VNets for resolution)
###############################################################
resource "azurerm_private_dns_resolver_virtual_network_link" "this" {
  for_each = local.enable_ruleset ? var.ruleset_vnet_links : {}

  name                      = each.key
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this[0].id
  virtual_network_id        = each.value
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_private_dns_resolver.this.id
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

  scope                            = azurerm_private_dns_resolver.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
