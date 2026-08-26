###############################################################
# MODULE: ServiceBus - Main
# Description: Azure Service Bus namespace (Microsoft.ServiceBus/
#              namespaces) with optional queues, topics + subscriptions,
#              SAS authorization rules, identity, network rules, lock, RBAC.
#              Secure-by-default: TLS 1.2. Entra-only auth available via
#              local_auth_enabled = false + RBAC data roles.
###############################################################

###############################################################
# Naming Convention — house prefix `sbns-` + the Naming submodule's
# suffix (Azure/naming v0.4.3 has no servicebus type, so we build
# manually, mirroring AzureMonitorWorkspace / ApplicationInsights).
# Convention: sbns-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    sbns-mgm-prod-frc-01
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
  name = var.name != null ? var.name : "sbns-${join("-", module.naming["this"].suffix)}"

  # Flatten topics -> subscriptions into a single "topic/sub" keyed map.
  subscriptions = merge([
    for tk, t in var.topics : {
      for sk, s in t.subscriptions : "${tk}/${sk}" => {
        topic_key = tk
        cfg       = s
      }
    }
  ]...)
}

###############################################################
# RESOURCE: Service Bus Namespace
###############################################################
resource "azurerm_servicebus_namespace" "this" {
  # checkov:skip=CKV_AZURE_204: public_network_access_enabled is exposed via var (default true). Basic/Standard have NO Private Endpoint, so a false default makes them unreachable; the private posture is Premium + Private Endpoint + public_network_access_enabled=false.
  # checkov:skip=CKV_AZURE_203: SAS/local auth is exposed via var.local_auth_enabled (default true) to avoid breaking connection-string consumers; set false for Entra-only (MS-recommended) and grant RBAC data roles via role_assignments.
  # checkov:skip=CKV_AZURE_201: CMK is exposed via var.customer_managed_key (Premium only; needs a caller-supplied UAMI + Key Vault key) — not forced by default because it breaks Basic/Standard and requires external resources this module cannot fabricate.
  # checkov:skip=CKV_AZURE_199: double (infrastructure) encryption is enabled through the same var.customer_managed_key block (infrastructure_encryption_enabled, default true when CMK is used) — Premium/CMK only, same rationale as CKV_AZURE_201.
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku                          = var.sku
  capacity                     = var.capacity
  premium_messaging_partitions = var.premium_messaging_partitions

  local_auth_enabled            = var.local_auth_enabled
  minimum_tls_version           = var.minimum_tls_version
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "network_rule_set" {
    for_each = var.network_rule_set != null ? [var.network_rule_set] : []
    content {
      default_action                = network_rule_set.value.default_action
      public_network_access_enabled = network_rule_set.value.public_network_access_enabled
      trusted_services_allowed      = network_rule_set.value.trusted_services_allowed
      ip_rules                      = network_rule_set.value.ip_rules

      dynamic "network_rules" {
        for_each = network_rule_set.value.network_rules
        content {
          subnet_id                            = network_rules.value.subnet_id
          ignore_missing_vnet_service_endpoint = network_rules.value.ignore_missing_vnet_service_endpoint
        }
      }
    }
  }

  # Optional CMK encryption (Premium only). infrastructure_encryption_enabled
  # provides double encryption at rest (CKV_AZURE_199).
  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key != null ? [var.customer_managed_key] : []
    content {
      key_vault_key_id                  = customer_managed_key.value.key_vault_key_id
      identity_id                       = customer_managed_key.value.identity_id
      infrastructure_encryption_enabled = customer_managed_key.value.infrastructure_encryption_enabled
    }
  }

  tags = var.tags
}

###############################################################
# RESOURCE: Queues
###############################################################
resource "azurerm_servicebus_queue" "this" {
  for_each = var.queues

  name         = coalesce(each.value.name, each.key)
  namespace_id = azurerm_servicebus_namespace.this.id

  max_size_in_megabytes                   = each.value.max_size_in_megabytes
  max_message_size_in_kilobytes           = each.value.max_message_size_in_kilobytes
  max_delivery_count                      = each.value.max_delivery_count
  lock_duration                           = each.value.lock_duration
  default_message_ttl                     = each.value.default_message_ttl
  auto_delete_on_idle                     = each.value.auto_delete_on_idle
  duplicate_detection_history_time_window = each.value.duplicate_detection_history_time_window
  requires_session                        = each.value.requires_session
  requires_duplicate_detection            = each.value.requires_duplicate_detection
  dead_lettering_on_message_expiration    = each.value.dead_lettering_on_message_expiration
  partitioning_enabled                    = each.value.partitioning_enabled
  batched_operations_enabled              = each.value.batched_operations_enabled
  express_enabled                         = each.value.express_enabled
  forward_to                              = each.value.forward_to
  forward_dead_lettered_messages_to       = each.value.forward_dead_lettered_messages_to
  status                                  = each.value.status
}

###############################################################
# RESOURCE: Topics
###############################################################
resource "azurerm_servicebus_topic" "this" {
  for_each = var.topics

  name         = coalesce(each.value.name, each.key)
  namespace_id = azurerm_servicebus_namespace.this.id

  max_size_in_megabytes                   = each.value.max_size_in_megabytes
  max_message_size_in_kilobytes           = each.value.max_message_size_in_kilobytes
  default_message_ttl                     = each.value.default_message_ttl
  auto_delete_on_idle                     = each.value.auto_delete_on_idle
  duplicate_detection_history_time_window = each.value.duplicate_detection_history_time_window
  requires_duplicate_detection            = each.value.requires_duplicate_detection
  partitioning_enabled                    = each.value.partitioning_enabled
  batched_operations_enabled              = each.value.batched_operations_enabled
  express_enabled                         = each.value.express_enabled
  support_ordering                        = each.value.support_ordering
  status                                  = each.value.status
}

###############################################################
# RESOURCE: Subscriptions (per topic)
###############################################################
resource "azurerm_servicebus_subscription" "this" {
  for_each = local.subscriptions

  name     = coalesce(each.value.cfg.name, split("/", each.key)[1])
  topic_id = azurerm_servicebus_topic.this[each.value.topic_key].id

  max_delivery_count                        = each.value.cfg.max_delivery_count
  lock_duration                             = each.value.cfg.lock_duration
  default_message_ttl                       = each.value.cfg.default_message_ttl
  auto_delete_on_idle                       = each.value.cfg.auto_delete_on_idle
  requires_session                          = each.value.cfg.requires_session
  dead_lettering_on_message_expiration      = each.value.cfg.dead_lettering_on_message_expiration
  dead_lettering_on_filter_evaluation_error = each.value.cfg.dead_lettering_on_filter_evaluation_error
  batched_operations_enabled                = each.value.cfg.batched_operations_enabled
  forward_to                                = each.value.cfg.forward_to
  forward_dead_lettered_messages_to         = each.value.cfg.forward_dead_lettered_messages_to
  status                                    = each.value.cfg.status
}

###############################################################
# RESOURCE: Namespace SAS Authorization Rules
###############################################################
resource "azurerm_servicebus_namespace_authorization_rule" "this" {
  for_each = var.authorization_rules

  name         = each.key
  namespace_id = azurerm_servicebus_namespace.this.id

  listen = each.value.listen
  send   = each.value.send
  manage = each.value.manage
}

###############################################################
# RESOURCE: Private Endpoints — delegated to ../PrivateEndpoint
# Target sub-resource "namespace"; DNS zone
# privatelink.servicebus.windows.net. Requires the Premium SKU.
###############################################################
module "private_endpoint" {
  source   = "../PrivateEndpoint"
  for_each = var.private_endpoints

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value.subnet_id
  tags                = var.tags

  private_endpoints = {
    (each.key) = {
      name                          = coalesce(each.value.name, "pe-${local.name}-${each.key}")
      resource_id                   = azurerm_servicebus_namespace.this.id
      subresource_names             = ["namespace"]
      private_ip_address            = each.value.private_ip_address
      member_name                   = each.value.member_name
      custom_network_interface_name = each.value.custom_network_interface_name
      private_dns_zone_group = each.value.private_dns_zone_ids != null ? {
        private_dns_zone_ids = each.value.private_dns_zone_ids
      } : null
      tags = each.value.tags
    }
  }
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_servicebus_namespace.this.id
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

  scope                            = azurerm_servicebus_namespace.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
