###############################################################
# MODULE: ApplicationGateway - Main
# Description: Azure Application Gateway v2 with WAF Policy
# Note: Public IP behind WAF is PoC only,
#       must go through Palo Alto FW in Prod
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
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
  name     = var.name != null ? var.name : module.naming["this"].result.application_gateway.name
  pip_name = "pip-${local.name}"
  waf_name = "waf-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"
}

###############################################################
# RESOURCE: WAF Policy
###############################################################
resource "azurerm_web_application_firewall_policy" "this" {
  # checkov:skip=CKV_AZURE_135: DRS 2.1 (Microsoft_DefaultRuleSet) is Microsoft's RECOMMENDED managed
  # rule set and supersedes the legacy OWASP CRS 3.1/3.2 that CKV_AZURE_135 pattern-matches (learn.microsoft.com
  # marks OWASP CRS as "legacy"). DRS 2.1 already includes and enables rule 944240 — "Remote Command Execution:
  # Java serialization and Log4j vulnerability (CVE-2021-44228, CVE-2021-45046)" — with NO rule_group_override
  # disabling it, so Log4j2 message lookup IS mitigated. The check only recognizes type="OWASP" ver 3.1/3.2 and
  # cannot see Microsoft_DefaultRuleSet; "fixing" it would mean downgrading to a legacy ruleset = a security
  # regression against Microsoft best practice. Skip is a scanner false-negative, not a missing control.
  name                = local.waf_name
  location            = var.location
  resource_group_name = var.resource_group_name

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = var.default_rule_set_version
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = var.bot_manager_rule_set_version
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Public IP (PoC only - Prod must go through Palo)
###############################################################
resource "azurerm_public_ip" "this" {
  count = var.create_public_ip ? 1 : 0

  name                = local.pip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.availability_zones

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
      Note      = "PoC only - Prod traffic must go through Palo Alto FW"
    }
  )
}

###############################################################
# RESOURCE: Application Gateway v2
###############################################################
resource "azurerm_application_gateway" "this" {
  name                              = local.name
  location                          = var.location
  resource_group_name               = var.resource_group_name
  firewall_policy_id                = azurerm_web_application_firewall_policy.this.id
  force_firewall_policy_association = var.force_firewall_policy_association
  zones                             = var.availability_zones
  http2_enabled                     = var.http2_enabled

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  # SSL policy — TLS 1.2+ minimum, strong cipher suites by default.
  # Predefined "AppGwSslPolicy20220101S" is Microsoft's strict baseline.
  ssl_policy {
    policy_type          = var.ssl_policy_type
    policy_name          = var.ssl_policy_type == "Predefined" ? var.ssl_policy_name : null
    min_protocol_version = var.ssl_policy_type == "CustomV2" ? var.ssl_policy_min_protocol_version : null
    cipher_suites        = var.ssl_policy_type == "CustomV2" ? var.ssl_policy_cipher_suites : null
  }

  # UAMI for Key Vault SSL cert access (used by AGIC and KV-managed certs).
  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type         = var.identity_type
      identity_ids = var.identity_ids
    }
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = var.appgw_subnet_id
  }

  # SSL certificate for TLS termination on the default HTTPS listener.
  # Sourced from Key Vault (secure pattern) — requires a UserAssigned identity (see var.identity_*)
  # with "Key Vault Certificate User" on the KV. Only emitted when a KV secret ID is supplied.
  # TLS termination with KV certs is limited to the v2 SKUs (this module is WAF_v2).
  dynamic "ssl_certificate" {
    for_each = var.ssl_certificate_key_vault_secret_id != null ? [1] : []
    content {
      name                = var.ssl_certificate_name
      key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
    }
  }

  # Frontend - Public IP (PoC)
  dynamic "frontend_ip_configuration" {
    for_each = var.create_public_ip ? [1] : []
    content {
      name                 = "frontend-public"
      public_ip_address_id = azurerm_public_ip.this[0].id
    }
  }

  # Frontend - Private IP
  frontend_ip_configuration {
    name                          = "frontend-private"
    subnet_id                     = var.appgw_subnet_id
    private_ip_address            = var.private_ip_address
    private_ip_address_allocation = var.private_ip_address != null ? "Static" : "Dynamic"
  }

  frontend_port {
    name = "http-80"
    port = 80
  }

  frontend_port {
    name = "https-443"
    port = 443
  }

  # Default backend (placeholder - will be configured by AGIC or manually)
  backend_address_pool {
    name = "default-backend-pool"
  }

  backend_http_settings {
    name                  = "default-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  # Default listener is HTTPS-only by default (secure baseline / CKV_AZURE_217).
  # NOTE (potentially breaking): an HTTPS listener requires an SSL certificate. Supply
  # var.ssl_certificate_key_vault_secret_id (a Key Vault PFX secret ID) — otherwise this
  # placeholder listener has no cert and `terraform apply` will fail at the Azure API.
  # These bootstrap listener/backend/rule blocks are placeholders and are in ignore_changes
  # below; AGIC (or manual config) manages the real listeners + certs post-create.
  http_listener {
    name                           = "default-https-listener"
    frontend_ip_configuration_name = "frontend-private"
    frontend_port_name             = "https-443"
    protocol                       = "Https"
    ssl_certificate_name           = var.ssl_certificate_name
  }

  request_routing_rule {
    name                       = "default-routing-rule"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "default-https-listener"
    backend_address_pool_name  = "default-backend-pool"
    backend_http_settings_name = "default-http-settings"
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    # Hardcoded prevent_destroy per critical-pivot pattern (v0.2.81). AppGW destroy severs HTTPS+TLS
    # for all backends + removes WAF security boundary. Same systemic protection as DdosProtection
    # v0.2.79 + ResourceGroup v0.2.76 + AlzManagement v0.2.77. Disabling requires module fork.
    prevent_destroy = true
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      http_listener,
      request_routing_rule,
      probe,
      frontend_port,
      redirect_configuration,
      url_path_map,
      ssl_certificate,
    ]
  }
}

###############################################################
# RBAC: Role Assignments
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_application_gateway.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_application_gateway.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
