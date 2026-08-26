###############################################################
# MODULE: ExpressRouteCircuit - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: erc-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    erc-con-prod-gwc-backbone
# Slug "erc" is the canonical upstream prefix from Azure/naming/azurerm.
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed from naming components."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm, con)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload suffix."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region for the ExpressRoute circuit"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

variable "service_provider_name" {
  type        = string
  description = "ExpressRoute service provider (e.g. DE-CIX, Equinix). Note: This module is scoped to the standard service-provider ER model. ExpressRouteDirect (express_route_port_id + bandwidth_in_gbps path) is OUT OF SCOPE — tracked as backlog enhancement."
  nullable    = false
}

variable "peering_location" {
  type        = string
  description = "Peering location (e.g. Frankfurt, Amsterdam). Note: This module is scoped to the standard service-provider ER model. ExpressRouteDirect (express_route_port_id + bandwidth_in_gbps path) is OUT OF SCOPE — tracked as backlog enhancement."
  nullable    = false
}

variable "bandwidth_in_mbps" {
  type        = number
  description = <<-EOT
  Circuit bandwidth in Mbps. Must be one of the Azure-supported values: 50, 100, 200, 500, 1000, 2000, 5000, 10000.

  Note: This module is scoped to the standard service-provider ER model. ExpressRouteDirect
  (express_route_port_id + bandwidth_in_gbps path) is OUT OF SCOPE — tracked as backlog enhancement.
  EOT
  nullable    = false

  validation {
    condition     = contains([50, 100, 200, 500, 1000, 2000, 5000, 10000], var.bandwidth_in_mbps)
    error_message = "bandwidth_in_mbps must be one of: 50, 100, 200, 500, 1000, 2000, 5000, 10000 (Azure-supported values)."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "sku_tier" {
  type        = string
  default     = "Standard"
  description = <<-EOT
  SKU tier for the ExpressRoute circuit. Valid values: Basic, Standard, Premium, Local.

  - Basic    — entry-level, limited route limits (preview in some regions)
  - Standard — regional connectivity
  - Premium  — global connectivity, higher route limits
  - Local    — discounted local-only connectivity; REQUIRES sku_family = "UnlimitedData"

  Note: Local + MeteredData is rejected by the Azure API.
  EOT

  validation {
    condition     = contains(["Basic", "Standard", "Premium", "Local"], var.sku_tier)
    error_message = "sku_tier must be one of: Basic, Standard, Premium, Local."
  }

  validation {
    condition     = var.sku_tier != "Local" || var.sku_family == "UnlimitedData"
    error_message = "sku_tier = \"Local\" requires sku_family = \"UnlimitedData\" (Azure API rejects Local + MeteredData)."
  }
}

variable "sku_family" {
  type        = string
  default     = "MeteredData"
  description = "SKU family (MeteredData or UnlimitedData)"

  validation {
    condition     = contains(["MeteredData", "UnlimitedData"], var.sku_family)
    error_message = "sku_family must be MeteredData or UnlimitedData."
  }
}

variable "allow_classic_operations" {
  type        = bool
  default     = false
  description = "Allow classic operations on the circuit"
}

###############################################################
# AZURE PRIVATE PEERING
# Configure the BGP peering session for VNet/vWAN connectivity.
# Set to null to defer peering configuration (e.g. while waiting
# for the provider to provision the circuit on their side).
###############################################################
variable "private_peering" {
  type = object({
    peer_asn                      = number
    primary_peer_address_prefix   = string
    secondary_peer_address_prefix = string
    vlan_id                       = number
    shared_key                    = optional(string)
    ipv4_enabled                  = optional(bool, true)
  })
  default     = null
  sensitive   = true
  description = <<-EOT
  Azure Private Peering configuration. Set to null to skip peering creation.

  - `peer_asn` — On-premises BGP ASN.
  - `primary_peer_address_prefix` — /30 subnet for the primary BGP session.
  - `secondary_peer_address_prefix` — /30 subnet for the secondary BGP session.
  - `vlan_id` — VLAN tag assigned by the provider.
  - `shared_key` — Optional MD5 BGP authentication key.
  - `ipv4_enabled` — Enable IPv4 family (default true).

  NOTE: AzurePrivatePeering can only be created once the circuit has been
  provisioned by the service provider (serviceProviderProvisioningState =
  "Provisioned"). Apply this module twice if needed:
    1. With private_peering = null  → creates circuit, captures serviceKey
    2. Share serviceKey with provider; wait for provisioning
    3. With private_peering = {...} → adds the peering
  EOT

  # F-6 — BGP ASN reserved validator
  validation {
    condition = (
      var.private_peering == null || (
        !(var.private_peering.peer_asn >= 65515 && var.private_peering.peer_asn <= 65520) &&
        var.private_peering.peer_asn != 12076
      )
    )
    error_message = "private_peering.peer_asn must not be in Azure-reserved range 65515-65520 nor Microsoft's 12076."
  }

  # F-7 — VLAN range validator
  validation {
    condition     = var.private_peering == null || (var.private_peering.vlan_id >= 1 && var.private_peering.vlan_id <= 4094)
    error_message = "private_peering.vlan_id must be in range 1-4094 (802.1Q VLAN ID)."
  }

  # F-8 — /30 CIDR validators
  validation {
    condition = (
      var.private_peering == null || (
        can(cidrhost(var.private_peering.primary_peer_address_prefix, 0)) &&
        split("/", var.private_peering.primary_peer_address_prefix)[1] == "30" &&
        can(cidrhost(var.private_peering.secondary_peer_address_prefix, 0)) &&
        split("/", var.private_peering.secondary_peer_address_prefix)[1] == "30"
      )
    )
    error_message = "private_peering primary/secondary peer address prefixes must be /30 CIDR blocks."
  }
}

###############################################################
# MICROSOFT PEERING (F-3)
# Optional Microsoft Peering BGP config for Office 365 / Azure
# PaaS reachability over ER.
# Set to null to skip Microsoft Peering.
###############################################################
variable "microsoft_peering" {
  type = object({
    peer_asn                      = number
    primary_peer_address_prefix   = string
    secondary_peer_address_prefix = string
    vlan_id                       = number
    shared_key                    = optional(string)
    ipv4_enabled                  = optional(bool, true)
    microsoft_peering_config = object({
      advertised_public_prefixes = list(string)
      advertised_communities     = optional(list(string))
      customer_asn               = optional(number)
      routing_registry_name      = optional(string)
    })
  })
  default     = null
  sensitive   = true
  description = <<-EOT
  Optional Microsoft Peering BGP config (for Office 365 / Azure PaaS reachability over ER).
  Set to null to skip Microsoft Peering. Mirror shape of var.private_peering plus
  microsoft_peering_config sub-block with advertised_public_prefixes (the public IP
  ranges your AS will advertise via the Microsoft Peering).

  - `peer_asn` — On-premises BGP ASN.
  - `primary_peer_address_prefix` — /30 subnet for the primary BGP session.
  - `secondary_peer_address_prefix` — /30 subnet for the secondary BGP session.
  - `vlan_id` — VLAN tag assigned by the provider (must differ from private_peering.vlan_id).
  - `shared_key` — Optional MD5 BGP authentication key.
  - `ipv4_enabled` — Enable IPv4 family (default true).
  - `microsoft_peering_config.advertised_public_prefixes` — List of public IP prefixes to advertise.
  - `microsoft_peering_config.advertised_communities` — Optional BGP community strings.
  - `microsoft_peering_config.customer_asn` — Optional customer ASN for prefix ownership validation.
  - `microsoft_peering_config.routing_registry_name` — Optional routing registry (e.g. ARIN, RIPE).
  EOT

  # F-6 — BGP ASN reserved validator
  validation {
    condition = (
      var.microsoft_peering == null || (
        !(var.microsoft_peering.peer_asn >= 65515 && var.microsoft_peering.peer_asn <= 65520) &&
        var.microsoft_peering.peer_asn != 12076
      )
    )
    error_message = "microsoft_peering.peer_asn must not be in Azure-reserved range 65515-65520 nor Microsoft's 12076."
  }

  # F-7 — VLAN range validator
  validation {
    condition     = var.microsoft_peering == null || (var.microsoft_peering.vlan_id >= 1 && var.microsoft_peering.vlan_id <= 4094)
    error_message = "microsoft_peering.vlan_id must be in range 1-4094 (802.1Q VLAN ID)."
  }

  # F-8 — /30 CIDR validators
  validation {
    condition = (
      var.microsoft_peering == null || (
        can(cidrhost(var.microsoft_peering.primary_peer_address_prefix, 0)) &&
        split("/", var.microsoft_peering.primary_peer_address_prefix)[1] == "30" &&
        can(cidrhost(var.microsoft_peering.secondary_peer_address_prefix, 0)) &&
        split("/", var.microsoft_peering.secondary_peer_address_prefix)[1] == "30"
      )
    )
    error_message = "microsoft_peering primary/secondary peer address prefixes must be /30 CIDR blocks."
  }
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional management lock (CanNotDelete or ReadOnly)"

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "Lock kind must be CanNotDelete or ReadOnly."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}
