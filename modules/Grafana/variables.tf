###############################################################
# MODULE: Grafana - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  description = "Explicit Grafana name override (escape hatch). If null, derived from naming convention via ../Naming."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Either var.name must be set OR all 4 naming components (subscription_acronym, environment, region_code, workload) must be non-null."
  }
}

variable "subscription_acronym" {
  type        = string
  description = "Subscription acronym (e.g. mgm, con)"
  default     = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  description = "Environment (e.g. prod, nprd)"
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  description = "Region code (e.g. gwc, weu)"
  default     = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  description = "Workload name for naming convention (e.g. 'monitoring', 'platform')."
  type        = string
  default     = "grafana"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

###############################################################
# CALLER-PROVIDED RESOURCE GROUP AND IDENTITY (F-2 BREAKING)
###############################################################
variable "resource_group_name" {
  description = "Name of the resource group where Grafana will be deployed. Must be created by the caller (e.g. via ../ResourceGroup at root)."
  type        = string
  nullable    = false
}

variable "user_assigned_identity_id" {
  description = "ARM ID of an existing User-Assigned Managed Identity to attach to Grafana. Compose with ../ManagedIdentity at root."
  type        = string
  nullable    = false
}

variable "user_assigned_identity_principal_id" {
  description = "Principal ID (object ID) of the UAMI. Used for role assignments. Required because Grafana SystemAssigned MI auto-assigns Monitoring Reader at AMW scope but UAMI does not."
  type        = string
  nullable    = false
}

###############################################################
# GRAFANA CONFIGURATION
###############################################################
variable "grafana_sku" {
  type        = string
  description = "Grafana instance SKU (Standard or Essential)"
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Essential"], var.grafana_sku)
    error_message = "grafana_sku must be Standard or Essential."
  }
}

variable "grafana_major_version" {
  type        = string
  description = "Grafana major version"
  default     = "11"
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public network access to Grafana. Set to false and use Private Endpoints in production."
  default     = false
}

variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy for Azure Managed Grafana. If null (default), env-driven: true for environment=='prod', false otherwise. Explicit override always wins. NOTE: This setting is Azure-immutable post-create — cannot be changed without recreate."
  type        = bool
  default     = null
  nullable    = true
}

variable "api_key_enabled" {
  type        = bool
  description = "Enable Grafana API keys"
  default     = false
}

variable "deterministic_outbound_ip_enabled" {
  type        = bool
  description = "Enable deterministic outbound IPs"
  default     = true
}

###############################################################
# AZURE MONITOR INTEGRATION
###############################################################
variable "azure_monitor_workspace_ids" {
  type        = list(string)
  description = "List of Azure Monitor Workspace IDs to integrate"
  default     = []
}

###############################################################
# IDENTITY ROLE ASSIGNMENTS
###############################################################
variable "identity_role_assignments" {
  description = <<-EOT
  A map of role assignments for the Grafana managed identity. The map key is
  deliberately arbitrary to avoid issues where map keys may be unknown at plan time.

  Canonical shape B (scope-based, MI is the principal — see CONTRIBUTING.md
  for the full convention).

  - `role_definition_id_or_name`             - (Required) Role definition ID or name.
  - `scope`                                  - (Required) Azure resource/MG scope.
  - `condition`                              - (Optional) ABAC condition for the role assignment.
  - `condition_version`                      - (Optional) Condition version. Valid values: "2.0".
  - `description`                            - (Optional) Description of the role assignment.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check. Default false.
  - `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    scope                                  = string
    condition                              = optional(string)
    condition_version                      = optional(string)
    description                            = optional(string)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string)
  }))
  default  = {}
  nullable = false
}

###############################################################
# GRAFANA RBAC (Entra ID Groups)
###############################################################
variable "grafana_admin_group_object_ids" {
  type        = list(string)
  description = "Object IDs of Entra ID groups to assign as Grafana Admin"
  default     = []
}

variable "grafana_editor_group_object_ids" {
  type        = list(string)
  description = "Object IDs of Entra ID groups to assign as Grafana Editor"
  default     = []
}

variable "grafana_viewer_group_object_ids" {
  type        = list(string)
  description = "Object IDs of Entra ID groups to assign as Grafana Viewer"
  default     = []
}

###############################################################
# PRIVATE ENDPOINT
###############################################################
variable "private_endpoint" {
  type = object({
    subnet_id                     = string
    private_dns_zone_ids          = optional(list(string))
    private_ip_address            = optional(string)
    custom_network_interface_name = optional(string)
  })
  default     = null
  description = <<-EOT
  Optional Private Endpoint for the Grafana instance (subresource "grafana").

  - `subnet_id`                     - (Required) Subnet ID for the PE NIC.
  - `private_dns_zone_ids`          - (Optional) DNS zone IDs to attach (e.g. privatelink.grafana.azure.com).
  - `private_ip_address`            - (Optional) Static private IP.
  - `custom_network_interface_name` - (Optional) Custom NIC name.
  EOT

  validation {
    condition     = var.private_endpoint == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", coalesce(try(var.private_endpoint.subnet_id, ""), "x")))
    error_message = "private_endpoint.subnet_id must be a valid Azure subnet resource ID."
  }

  validation {
    condition     = var.private_endpoint == null || var.private_endpoint.private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", coalesce(var.private_endpoint.private_ip_address, "x")))
    error_message = "private_endpoint.private_ip_address must be a valid IPv4 address."
  }
}

###############################################################
# MANAGED PRIVATE ENDPOINTS (Grafana → data sources)
###############################################################
variable "managed_private_endpoints" {
  type = map(object({
    private_link_resource_id     = string
    group_ids                    = optional(list(string))
    private_link_resource_region = optional(string)
    private_link_service_url     = optional(string)
    request_message              = optional(string)
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
  Managed Private Endpoints from Grafana to private data sources (e.g. AMPLS).
  Lets Grafana query Log Analytics / Azure Monitor over the private path so
  workspaces protected by NSP / private-only do not reject Grafana egress.

  Map key = short name used in the MPE resource name. Value:
  - `private_link_resource_id`     - (Required) Target resource ID (e.g. AMPLS id).
  - `group_ids`                    - (Optional) Subresource(s), e.g. ["azuremonitor"].
  - `private_link_resource_region` - (Optional) Region of the target.
  - `private_link_service_url`     - (Optional) FQDN for Private Link Service targets.
  - `request_message`              - (Optional) Connection request message.
  EOT
}

###############################################################
# LOCK
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Controls the Resource Lock configuration for this resource.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
  nullable    = false
}
